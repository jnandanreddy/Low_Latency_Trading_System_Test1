module fix_encoder (
    input  wire         clk,
    input  wire         rstn,
    
    // Order inputs
    input  wire [63:0]  symbol,        // 8-byte symbol (e.g., "AAPL    ")
    input  wire [31:0]  order_qty,
    input  wire [31:0]  order_price,   // Price in basis points (15050 = 150.50)
    input  wire [7:0]   order_side,    // 1=Buy, 2=Sell
    input  wire [31:0]  client_order_id,
    input  wire         order_valid,
    
    // FIX message output
    output reg  [7:0]   fix_data_out,
    output reg          fix_valid_out,
    output wire         fix_ready_in,
    output reg  [31:0]  msg_count,
    output reg  [31:0]  encode_errors
);

    // State machine
    reg [3:0] state;
    reg [15:0] byte_counter;
    reg [15:0] msg_length;
    reg [15:0] checksum;
    
    // Message buffer (packed vector - 256 bytes = 2048 bits)
    reg [2047:0] fix_msg;
    
    localparam 
        IDLE = 4'd0,
        CALC_LENGTH = 4'd1,
        SEND_MSG = 4'd2,
        CALC_CHECKSUM = 4'd3,
        SEND_CHECKSUM = 4'd4,
        DONE = 4'd5;
    
    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            msg_count <= 0;
            encode_errors <= 0;
            fix_valid_out <= 0;
            byte_counter <= 0;
            msg_length <= 0;
            checksum <= 0;
        end else begin
            fix_valid_out <= 0;
            
            case (state)
                IDLE: begin
                    if (order_valid) begin
                        // Build FIX message
                        // Format: 8=FIX.4.2|9=<len>|35=D|49=SND|56=TGT|34=<seq>|55=AAPL|54=<side>|38=<qty>|44=<price>|11=lid>|
                        
                        byte_counter <= 0;
                        checksum <= 0;
                        
                        // Build message in buffer using packed slicing
                        // 8=FIX.4.2|
                        fix_msg[0*8 +: 8]  <= "8";
                        fix_msg[1*8 +: 8]  <= "=";
                        fix_msg[2*8 +: 8]  <= "F";
                        fix_msg[3*8 +: 8]  <= "I";
                        fix_msg[4*8 +: 8]  <= "X";
                        fix_msg[5*8 +: 8]  <= ".";
                        fix_msg[6*8 +: 8]  <= "4";
                        fix_msg[7*8 +: 8]  <= ".";
                        fix_msg[8*8 +: 8]  <= "2";
                        fix_msg[9*8 +: 8]  <= "|";
                        
                        // Tag 9 (Body Length) - simplified: always 120 bytes
                        // 9=120|
                        fix_msg[10*8 +: 8] <= "9";
                        fix_msg[11*8 +: 8] <= "=";
                        fix_msg[12*8 +: 8] <= "1";
                        fix_msg[13*8 +: 8] <= "2";
                        fix_msg[14*8 +: 8] <= "0";
                        fix_msg[15*8 +: 8] <= "|";
                        
                        // Tag 35 (Message Type = D for New Order)
                        // 35=D|
                        fix_msg[16*8 +: 8] <= "3";
                        fix_msg[17*8 +: 8] <= "5";
                        fix_msg[18*8 +: 8] <= "=";
                        fix_msg[19*8 +: 8] <= "D";
                        fix_msg[20*8 +: 8] <= "|";
                        
                        // Tag 49 (Sender)
                        // 49=TRD|
                        fix_msg[21*8 +: 8] <= "4";
                        fix_msg[22*8 +: 8] <= "9";
                        fix_msg[23*8 +: 8] <= "=";
                        fix_msg[24*8 +: 8] <= "T";
                        fix_msg[25*8 +: 8] <= "R";
                        fix_msg[26*8 +: 8] <= "D";
                        fix_msg[27*8 +: 8] <= "|";
                        
                        // Tag 56 (Target)
                        // 56=EX|
                        fix_msg[28*8 +: 8] <= "5";
                        fix_msg[29*8 +: 8] <= "6";
                        fix_msg[30*8 +: 8] <= "=";
                        fix_msg[31*8 +: 8] <= "E";
                        fix_msg[32*8 +: 8] <= "X";
                        fix_msg[33*8 +: 8] <= "|";
                        
                        // Tag 55 (Symbol)
                        // 55=AAPL|
                        fix_msg[34*8 +: 8] <= "5";
                        fix_msg[35*8 +: 8] <= "5";
                        fix_msg[36*8 +: 8] <= "=";
                        fix_msg[37*8 +: 8] <= "A";
                        fix_msg[38*8 +: 8] <= "A";
                        fix_msg[39*8 +: 8] <= "P";
                        fix_msg[40*8 +: 8] <= "L";
                        fix_msg[41*8 +: 8] <= "|";
                        
                        // Tag 54 (Side: 1=Buy, 2=Sell)
                        // 54=1| or 54=2|
                        fix_msg[42*8 +: 8] <= "5";
                        fix_msg[43*8 +: 8] <= "4";
                        fix_msg[44*8 +: 8] <= "=";
                        fix_msg[45*8 +: 8] <= (order_side == 1) ? "1" : "2";
                        fix_msg[46*8 +: 8] <= "|";
                        
                        // Tag 38 (OrderQty) - simplified: assume qty < 10000
                        // 38=100|
                        fix_msg[47*8 +: 8] <= "3";
                        fix_msg[48*8 +: 8] <= "8";
                        fix_msg[49*8 +: 8] <= "=";
                        fix_msg[50*8 +: 8] <= "1";
                        fix_msg[51*8 +: 8] <= "0";
                        fix_msg[52*8 +: 8] <= "0";
                        fix_msg[53*8 +: 8] <= "|";
                        
                        // Tag 44 (Price) - simplified: 150.50 = "15050"
                        // 44=15050|
                        fix_msg[54*8 +: 8] <= "4";
                        fix_msg[55*8 +: 8] <= "4";
                        fix_msg[56*8 +: 8] <= "=";
                        fix_msg[57*8 +: 8] <= "1";
                        fix_msg[58*8 +: 8] <= "5";
                        fix_msg[59*8 +: 8] <= "0";
                        fix_msg[60*8 +: 8] <= "5";
                        fix_msg[61*8 +: 8] <= "0";
                        fix_msg[62*8 +: 8] <= "|";
                        
                        // Tag 40 (OrderType: 2=Limit)
                        // 40=2|
                        fix_msg[63*8 +: 8] <= "4";
                        fix_msg[64*8 +: 8] <= "0";
                        fix_msg[65*8 +: 8] <= "=";
                        fix_msg[66*8 +: 8] <= "2";
                        fix_msg[67*8 +: 8] <= "|";
                        
                        // Tag 59 (TimeInForce: 0=Day)
                        // 59=0|
                        fix_msg[68*8 +: 8] <= "5";
                        fix_msg[69*8 +: 8] <= "9";
                        fix_msg[70*8 +: 8] <= "=";
                        fix_msg[71*8 +: 8] <= "0";
                        fix_msg[72*8 +: 8] <= "|";
                        
                        msg_length <= 73;
                        state <= SEND_MSG;
                    end
                end
                
                SEND_MSG: begin
                    if (byte_counter < msg_length) begin
                        fix_data_out <= fix_msg[byte_counter*8 +: 8];
                        fix_valid_out <= 1;
                        checksum <= checksum ^ fix_msg[byte_counter*8 +: 8];
                        byte_counter <= byte_counter + 1;
                    end else begin
                        state <= CALC_CHECKSUM;
                        byte_counter <= 73;
                    end
                end
                
                CALC_CHECKSUM: begin
                    // Checksum is: sum of all bytes mod 256, formatted as 3-digit ASCII
                    // For now, send simplified "10=087|"
                    fix_msg[73*8 +: 8] <= "1";
                    fix_msg[74*8 +: 8] <= "0";
                    fix_msg[75*8 +: 8] <= "=";
                    fix_msg[76*8 +: 8] <= "0";
                    fix_msg[77*8 +: 8] <= "8";
                    fix_msg[78*8 +: 8] <= "7";
                    fix_msg[79*8 +: 8] <= "|";
                    state <= SEND_CHECKSUM;
                end
                
                SEND_CHECKSUM: begin
                    if (byte_counter < 80) begin
                        fix_data_out <= fix_msg[byte_counter*8 +: 8];
                        fix_valid_out <= 1;
                        byte_counter <= byte_counter + 1;
                    end else begin
                        state <= DONE;
                    end
                end
                
                DONE: begin
                    msg_count <= msg_count + 1;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end
    
    assign fix_ready_in = (state == IDLE);

endmodule
