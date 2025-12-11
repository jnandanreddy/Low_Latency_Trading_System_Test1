module fix_decoder (
    input  wire         clk,
    input  wire         rstn,

    // From Ethernet RX
    input  wire [7:0]   rx_data_in,
    input  wire         rx_valid_in,

    // Decoded execution report
    output reg  [63:0]  order_id,          // Tag 37
    output reg  [63:0]  client_order_id,   // Tag 11
    output reg  [7:0]   exec_type,         // Tag 150
    output reg  [7:0]   order_status,      // Tag 39
    output reg  [31:0]  cum_qty,           // Tag 14
    output reg  [31:0]  leaves_qty,        // Tag 151
    output reg  [31:0]  last_qty,          // Tag 32
    output reg  [31:0]  last_price,        // Tag 31
    output reg          exec_report_valid,

    // Statistics
    output reg  [31:0]  msg_count,
    output reg  [31:0]  parse_errors
);

    // Parser state machine
    reg [3:0] state;
    localparam
        IDLE = 4'd0,
        READ_TAG = 4'd1,
        READ_EQUALS = 4'd2,
        READ_VALUE = 4'd3,
        READ_SOH = 4'd4,
        VALIDATE_CHECKSUM = 4'd5,
        DECODE_DONE = 4'd6;

    reg [15:0] current_tag;
    reg [127:0] current_value;  // Max 16 bytes for value
    reg [7:0] value_index;
    reg [7:0] checksum_calc;
    reg [7:0] checksum_received;

    // ASCII to decimal conversion
    function [7:0] ascii_to_digit;
        input [7:0] ascii;
        begin
            ascii_to_digit = ascii - 8'h30;  // '0' = 0x30
        end
    endfunction

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            exec_report_valid <= 0;
            msg_count <= 0;
            parse_errors <= 0;
            current_tag <= 0;
            value_index <= 0;
            checksum_calc <= 0;
        end else begin
            exec_report_valid <= 0;

            case (state)
                IDLE: begin
                    if (rx_valid_in && rx_data_in == 8'h38) begin  // '8' = BeginString
                        state <= READ_TAG;
                        current_tag <= {8'h00, rx_data_in};
                        checksum_calc <= rx_data_in;
                    end
                end

                READ_TAG: begin
                    if (rx_valid_in) begin
                        checksum_calc <= checksum_calc + rx_data_in;

                        if (rx_data_in == 8'h3D) begin  // '=' found
                            state <= READ_VALUE;
                            value_index <= 0;
                            current_value <= 0;
                        end else if (rx_data_in >= 8'h30 && rx_data_in <= 8'h39) begin  // '0'-'9'
                            current_tag <= {current_tag[7:0], rx_data_in};
                        end else begin
                            state <= IDLE;  // Invalid character
                            parse_errors <= parse_errors + 1;
                        end
                    end
                end

                READ_VALUE: begin
                    if (rx_valid_in) begin
                        if (rx_data_in == 8'h01) begin  // SOH (0x01) = field separator
                            // Store value based on tag
                            case (current_tag)
                                16'h3337: order_id <= current_value[63:0];        // Tag 37
                                16'h3131: client_order_id <= current_value[63:0]; // Tag 11
                                16'h313530: exec_type <= current_value[7:0];      // Tag 150
                                16'h3339: order_status <= current_value[7:0];     // Tag 39
                                16'h3134: cum_qty <= current_value[31:0];         // Tag 14
                                16'h313531: leaves_qty <= current_value[31:0];    // Tag 151
                                16'h3332: last_qty <= current_value[31:0];        // Tag 32
                                16'h3331: last_price <= current_value[31:0];      // Tag 31
                                16'h3130: begin  // Tag 10 = Checksum
                                    checksum_received <= current_value[7:0];
                                    state <= VALIDATE_CHECKSUM;
                                end
                            endcase

                            if (current_tag != 16'h3130) begin  // Not checksum tag
                                state <= READ_TAG;
                                current_tag <= 0;
                            end
                        end else begin
                            current_value <= {current_value[119:0], rx_data_in};
                            value_index <= value_index + 1;
                            checksum_calc <= checksum_calc + rx_data_in;
                        end
                    end
                end

                VALIDATE_CHECKSUM: begin
                    if ((checksum_calc & 8'hFF) == checksum_received) begin
                        state <= DECODE_DONE;
                    end else begin
                        state <= IDLE;
                        parse_errors <= parse_errors + 1;
                    end
                end

                DECODE_DONE: begin
                    exec_report_valid <= 1;
                    msg_count <= msg_count + 1;
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule
