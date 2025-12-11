module tcp_session_manager (
    input  wire         clk,
    input  wire         rstn,

    // Configuration
    input  wire [31:0]  remote_ip,
    input  wire [15:0]  remote_port,
    input  wire [15:0]  local_port,

    // Control
    input  wire         connect_req,
    input  wire         disconnect_req,

    // TCP state
    output reg  [3:0]   tcp_state,
    output reg          connection_established,
    output reg          connection_closed,

    // Data interface
    input  wire [7:0]   tx_data_in,
    input  wire         tx_valid_in,
    output wire         tx_ready_out,

    output reg  [7:0]   rx_data_out,
    output reg          rx_valid_out,

    // To/From IP layer
    output reg  [63:0]  tcp_tx_packet,
    output reg          tcp_tx_valid,
    input  wire         tcp_tx_ready,

    input  wire [63:0]  tcp_rx_packet,
    input  wire         tcp_rx_valid,

    // Statistics
    output reg  [31:0]  bytes_sent,
    output reg  [31:0]  bytes_received,
    output reg  [31:0]  retransmit_count
);

    // TCP State Machine
    localparam
        CLOSED = 4'd0,
        SYN_SENT = 4'd1,
        SYN_RECEIVED = 4'd2,
        ESTABLISHED = 4'd3,
        FIN_WAIT_1 = 4'd4,
        FIN_WAIT_2 = 4'd5,
        CLOSING = 4'd6,
        TIME_WAIT = 4'd7,
        CLOSE_WAIT = 4'd8,
        LAST_ACK = 4'd9;

    reg [31:0] seq_num;
    reg [31:0] ack_num;
    reg [15:0] window_size;

    // Simplified TCP header construction
    reg [15:0] src_port_reg;
    reg [15:0] dst_port_reg;

    always @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            tcp_state <= CLOSED;
            connection_established <= 0;
            connection_closed <= 1;
            seq_num <= 32'h00001000;  // Initial sequence number
            bytes_sent <= 0;
            bytes_received <= 0;
        end else begin
            case (tcp_state)
                CLOSED: begin
                    connection_closed <= 1;
                    connection_established <= 0;

                    if (connect_req) begin
                        // Send SYN
                        tcp_state <= SYN_SENT;
                        src_port_reg <= local_port;
                        dst_port_reg <= remote_port;
                        tcp_tx_packet <= {src_port_reg, dst_port_reg, seq_num};
                        tcp_tx_valid <= 1;
                        seq_num <= seq_num + 1;
                    end
                end

                SYN_SENT: begin
                    if (tcp_rx_valid) begin
                        // Check for SYN-ACK
                        // Simplified: assume valid SYN-ACK received
                        tcp_state <= ESTABLISHED;
                        connection_established <= 1;
                        connection_closed <= 0;
                        ack_num <= tcp_rx_packet[31:0] + 1;
                    end
                end

                ESTABLISHED: begin
                    tcp_tx_valid <= 0;

                    // Data transmission
                    if (tx_valid_in && tcp_tx_ready) begin
                        tcp_tx_packet <= {src_port_reg, dst_port_reg, tx_data_in, 24'h000000};
                        tcp_tx_valid <= 1;
                        bytes_sent <= bytes_sent + 1;
                        seq_num <= seq_num + 1;
                    end

                    // Data reception
                    if (tcp_rx_valid) begin
                        rx_data_out <= tcp_rx_packet[63:56];
                        rx_valid_out <= 1;
                        bytes_received <= bytes_received + 1;
                        ack_num <= ack_num + 1;
                    end else begin
                        rx_valid_out <= 0;
                    end

                    // Disconnect
                    if (disconnect_req) begin
                        tcp_state <= FIN_WAIT_1;
                    end
                end

                FIN_WAIT_1: begin
                    // Send FIN
                    tcp_tx_packet <= {src_port_reg, dst_port_reg, 32'hFFFFFFFF};
                    tcp_tx_valid <= 1;
                    tcp_state <= FIN_WAIT_2;
                end

                FIN_WAIT_2: begin
                    if (tcp_rx_valid) begin
                        // Received ACK for FIN
                        tcp_state <= TIME_WAIT;
                    end
                end

                TIME_WAIT: begin
                    // Wait 2*MSL (simplified: immediate close)
                    tcp_state <= CLOSED;
                    connection_established <= 0;
                    connection_closed <= 1;
                end
            endcase
        end
    end

    assign tx_ready_out = (tcp_state == ESTABLISHED) && tcp_tx_ready;

endmodule
