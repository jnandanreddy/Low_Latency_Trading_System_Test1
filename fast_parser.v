module fast_parser (
    input  wire         clk,
    input  wire         rstn,
    
    // Input: Raw FAST message (from UDP payload)
    input  wire [7:0]   fast_data_in,     // Byte stream
    input  wire         fast_valid_in,
    output wire         fast_ready_out,
    
    // Output: Decoded fields
    output reg  [31:0]  template_id,
    output reg  [63:0]  symbol,          // 8-char symbol (packed ASCII)
    output reg  [31:0]  price,           // Fixed-point price
    output reg  [31:0]  quantity,
    output reg  [7:0]   side,            // 0=Buy, 1=Sell
    output reg  [63:0]  timestamp,
    output reg          decoded_valid,
    
    // Statistics
    output reg  [31:0]  msg_count,
    output reg  [31:0]  decode_errors
);

    // ========== Parser State Machine ==========
    localparam IDLE          = 4'd0;
    localparam READ_PMAP     = 4'd1;  // Presence Map
    localparam READ_TEMPLATE = 4'd2;
    localparam READ_SYMBOL   = 4'd3;
    localparam READ_PRICE    = 4'd4;
    localparam READ_QTY      = 4'd5;
    localparam READ_SIDE     = 4'd6;
    localparam READ_TIME     = 4'd7;
    localparam DECODE_DONE   = 4'd8;
    
    reg [3:0] state;
    
    // ========== FAST Presence Map (PMAP) ==========
    reg [7:0] pmap;
    
    // ========== Field Buffers (PACKED for synthesis) ==========
    // 16 bytes = 128 bits packed vector
    reg [127:0] byte_buffer;
    reg [3:0]   byte_count;
    
    // ========== Previous Values (for Copy/Delta operators) ==========
    reg [31:0] prev_price;
    reg [31:0] prev_qty;
    
    // ========== Temporary decode registers ==========
    reg [31:0] varint_result;
    
    // ========== Parsing Logic ==========
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state         <= IDLE;
            byte_count    <= 4'd0;
            byte_buffer   <= 128'd0;
            pmap          <= 8'd0;
            template_id   <= 32'd0;
            symbol        <= 64'd0;
            price         <= 32'd0;
            quantity      <= 32'd0;
            side          <= 8'd0;
            timestamp     <= 64'd0;
            decoded_valid <= 1'b0;
            msg_count     <= 32'd0;
            decode_errors <= 32'd0;
            prev_price    <= 32'd0;
            prev_qty      <= 32'd0;
            varint_result <= 32'd0;
        end else begin
            case (state)
                // ========== IDLE: Wait for message start ==========
                IDLE: begin
                    decoded_valid <= 1'b0;
                    if (fast_valid_in) begin
                        byte_count  <= 4'd0;
                        byte_buffer <= 128'd0;
                        state       <= READ_PMAP;
                    end
                end
                
                // ========== READ PMAP: Presence Map (1 byte) ==========
                READ_PMAP: begin
                    if (fast_valid_in) begin
                        pmap  <= fast_data_in;
                        state <= READ_TEMPLATE;
                    end
                end
                
                // ========== READ TEMPLATE: Template ID (variable length) ==========
                READ_TEMPLATE: begin
                    if (fast_valid_in) begin
                        // Store byte into packed buffer
                        byte_buffer[byte_count*8 +: 8] <= fast_data_in;
                        byte_count <= byte_count + 1;
                        
                        // MSB = 1 indicates last byte of varint
                        if (fast_data_in[7] == 1'b1) begin
                            // Simplified: use lower 7 bits as template ID
                            template_id <= {25'd0, fast_data_in[6:0]};
                            byte_count  <= 4'd0;
                            byte_buffer <= 128'd0;
                            state       <= READ_SYMBOL;
                        end
                    end
                end
                
                // ========== READ SYMBOL: 8-char ASCII symbol ==========
                READ_SYMBOL: begin
                    if (fast_valid_in) begin
                        // Store each byte into packed buffer
                        byte_buffer[byte_count*8 +: 8] <= fast_data_in;
                        byte_count <= byte_count + 1;
                        
                        if (byte_count == 4'd7) begin
                            // Pack 8 bytes into 64-bit symbol
                            // byte_buffer[63:0] contains bytes 0-7
                            symbol <= {byte_buffer[7:0],   byte_buffer[15:8],
                                       byte_buffer[23:16], byte_buffer[31:24],
                                       byte_buffer[39:32], byte_buffer[47:40],
                                       byte_buffer[55:48], fast_data_in};
                            byte_count  <= 4'd0;
                            byte_buffer <= 128'd0;
                            state       <= READ_PRICE;
                        end
                    end
                end
                
                // ========== READ PRICE: Price field (Delta operator) ==========
                READ_PRICE: begin
                    if (fast_valid_in) begin
                        // PMAP bit 4 indicates price field present
                        if (pmap[4] == 1'b1) begin
                            byte_buffer[byte_count*8 +: 8] <= fast_data_in;
                            byte_count <= byte_count + 1;
                            
                            // MSB = 1 indicates last byte
                            if (fast_data_in[7] == 1'b1) begin
                                // Simplified decode: use accumulated bytes
                                // Real FAST uses 7-bit chunks
                                price      <= prev_price + {25'd0, fast_data_in[6:0]};
                                prev_price <= prev_price + {25'd0, fast_data_in[6:0]};
                                byte_count  <= 4'd0;
                                byte_buffer <= 128'd0;
                                state       <= READ_QTY;
                            end
                        end else begin
                            // PMAP bit not set: Copy operator
                            price <= prev_price;
                            state <= READ_QTY;
                        end
                    end
                end
                
                // ========== READ QTY: Quantity (similar to price) ==========
                READ_QTY: begin
                    if (fast_valid_in) begin
                        // PMAP bit 3 indicates quantity present
                        if (pmap[3] == 1'b1) begin
                            byte_buffer[byte_count*8 +: 8] <= fast_data_in;
                            byte_count <= byte_count + 1;
                            
                            if (fast_data_in[7] == 1'b1) begin
                                quantity   <= {25'd0, fast_data_in[6:0]};
                                prev_qty   <= {25'd0, fast_data_in[6:0]};
                                byte_count  <= 4'd0;
                                byte_buffer <= 128'd0;
                                state       <= READ_SIDE;
                            end
                        end else begin
                            // Copy operator
                            quantity <= prev_qty;
                            state    <= READ_SIDE;
                        end
                    end
                end
                
                // ========== READ SIDE: Side (1 byte) ==========
                READ_SIDE: begin
                    if (fast_valid_in) begin
                        side  <= fast_data_in;
                        byte_count  <= 4'd0;
                        byte_buffer <= 128'd0;
                        state <= READ_TIME;
                    end
                end
                
                // ========== READ TIME: Timestamp (8 bytes) ==========
                READ_TIME: begin
                    if (fast_valid_in) begin
                        byte_buffer[byte_count*8 +: 8] <= fast_data_in;
                        byte_count <= byte_count + 1;
                        
                        if (byte_count == 4'd7) begin
                            // Pack 8 bytes into 64-bit timestamp
                            timestamp <= {byte_buffer[7:0],   byte_buffer[15:8],
                                          byte_buffer[23:16], byte_buffer[31:24],
                                          byte_buffer[39:32], byte_buffer[47:40],
                                          byte_buffer[55:48], fast_data_in};
                            byte_count  <= 4'd0;
                            byte_buffer <= 128'd0;
                            state       <= DECODE_DONE;
                        end
                    end
                end
                
                // ========== DECODE DONE: Output valid ==========
                DECODE_DONE: begin
                    decoded_valid <= 1'b1;
                    msg_count     <= msg_count + 1;
                    state         <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    // ========== Ready Signal ==========
    assign fast_ready_out = (state != IDLE);

endmodule
