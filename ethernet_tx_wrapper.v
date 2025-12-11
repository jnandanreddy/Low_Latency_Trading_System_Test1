module ethernet_tx_wrapper (
    input  wire         clk156,         // 156.25 MHz for 10G
    input  wire         rstn,
    
    // From FIX encoder
    input  wire [63:0]  fix_data_in,    // 64-bit AXI Stream
    input  wire         fix_valid_in,
    input  wire         fix_last_in,    // End of FIX message
    output wire         fix_ready_out,
    
    // To Ethernet MAC
    output reg  [63:0]  eth_tx_data,      // Changed to reg
    output reg          eth_tx_valid,     // Changed to reg
    output reg          eth_tx_last,      // Changed to reg
    input  wire         eth_tx_ready,
    
    // Statistics
    output reg  [31:0]  tx_frame_count,
    output reg  [31:0]  tx_byte_count
);

    // TCP/IP header construction - now with individual indexed elements
    reg [63:0] eth_header_0;
    reg [63:0] eth_header_1;
    
    reg [63:0] ip_header_0;
    reg [63:0] ip_header_1;
    reg [63:0] ip_header_2;
    
    reg [63:0] tcp_header_0;
    reg [63:0] tcp_header_1;
    reg [63:0] tcp_header_2;
    
    // State machine for packet construction
    reg [3:0] tx_state;
    localparam 
        TX_IDLE = 4'd0,
        TX_ETH_HDR = 4'd1,
        TX_IP_HDR = 4'd2,
        TX_TCP_HDR = 4'd3,
        TX_PAYLOAD = 4'd4,
        TX_CRC = 4'd5;
    
    // Pre-configure headers (now using individual regs)
    initial begin
        // Ethernet header: Dest MAC, Src MAC, EtherType=0x0800 (IP)
        eth_header_0 = {48'hFFFFFFFFFFFF, 16'h0000};  // Dest MAC (broadcast)
        eth_header_1 = {32'h12345678, 16'h0800, 16'h0000};  // Src MAC + EtherType
        
        // IP header: Ver=4, IHL=5, TOS=0, Len=..., ID=1, Flags=0, TTL=64, Proto=6 (TCP)
        ip_header_0 = {8'h45, 8'h00, 16'h0000, 16'h0001, 16'h4000};
        ip_header_1 = {8'h40, 8'h06, 16'h0000, 32'hC0A80101}; // TTL, Proto, Checksum, Src IP
        ip_header_2 = {32'hC0A80102, 32'h00000000};  // Dest IP
        
        // TCP header: Src Port, Dst Port, Seq, Ack, Flags
        tcp_header_0 = {16'd1234, 16'd5678, 32'h00000001};
        tcp_header_1 = {32'h00000001, 16'h5018, 16'hFFFF};  // Ack, Flags, Window
        tcp_header_2 = {16'h0000, 16'h0000, 32'h00000000};  // Checksum, Urgent
    end
    
    reg [7:0] hdr_index;
    
    always @(posedge clk156 or negedge rstn) begin
        if (!rstn) begin
            tx_state <= TX_IDLE;
            eth_tx_valid <= 0;
            eth_tx_last <= 0;
            eth_tx_data <= 64'd0;
            tx_frame_count <= 0;
            tx_byte_count <= 0;
            hdr_index <= 0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    eth_tx_valid <= 0;
                    eth_tx_last <= 0;
                    if (fix_valid_in) begin
                        tx_state <= TX_ETH_HDR;
                        hdr_index <= 0;
                    end
                end
                
                TX_ETH_HDR: begin
                    if (eth_tx_ready) begin
                        // Use case statement to select the right header element
                        case (hdr_index)
                            8'd0: eth_tx_data <= eth_header_0;
                            8'd1: eth_tx_data <= eth_header_1;
                            default: eth_tx_data <= 64'd0;
                        endcase
                        
                        eth_tx_valid <= 1;
                        eth_tx_last <= 0;
                        hdr_index <= hdr_index + 1;
                        
                        if (hdr_index == 1) begin
                            tx_state <= TX_IP_HDR;
                            hdr_index <= 0;
                        end
                    end else begin
                        eth_tx_valid <= 0;
                    end
                end
                
                TX_IP_HDR: begin
                    if (eth_tx_ready) begin
                        case (hdr_index)
                            8'd0: eth_tx_data <= ip_header_0;
                            8'd1: eth_tx_data <= ip_header_1;
                            8'd2: eth_tx_data <= ip_header_2;
                            default: eth_tx_data <= 64'd0;
                        endcase
                        
                        eth_tx_valid <= 1;
                        eth_tx_last <= 0;
                        hdr_index <= hdr_index + 1;
                        
                        if (hdr_index == 2) begin
                            tx_state <= TX_TCP_HDR;
                            hdr_index <= 0;
                        end
                    end else begin
                        eth_tx_valid <= 0;
                    end
                end
                
                TX_TCP_HDR: begin
                    if (eth_tx_ready) begin
                        case (hdr_index)
                            8'd0: eth_tx_data <= tcp_header_0;
                            8'd1: eth_tx_data <= tcp_header_1;
                            8'd2: eth_tx_data <= tcp_header_2;
                            default: eth_tx_data <= 64'd0;
                        endcase
                        
                        eth_tx_valid <= 1;
                        eth_tx_last <= 0;
                        hdr_index <= hdr_index + 1;
                        
                        if (hdr_index == 2) begin
                            tx_state <= TX_PAYLOAD;
                        end
                    end else begin
                        eth_tx_valid <= 0;
                    end
                end
                
                TX_PAYLOAD: begin
                    if (eth_tx_ready && fix_valid_in) begin
                        eth_tx_data <= fix_data_in;
                        eth_tx_valid <= 1;
                        eth_tx_last <= fix_last_in;
                        tx_byte_count <= tx_byte_count + 8;
                        
                        if (fix_last_in) begin
                            tx_state <= TX_IDLE;
                            tx_frame_count <= tx_frame_count + 1;
                        end
                    end else begin
                        eth_tx_valid <= 0;
                        eth_tx_last <= 0;
                    end
                end
                
                default: begin
                    tx_state <= TX_IDLE;
                    eth_tx_valid <= 0;
                    eth_tx_last <= 0;
                end
            endcase
        end
    end
    
    assign fix_ready_out = (tx_state == TX_PAYLOAD) && eth_tx_ready;

endmodule
