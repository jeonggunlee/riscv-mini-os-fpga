`timescale 1ns/1ps
`default_nettype none
module tb_shell;
    localparam integer APP_BYTES = `APP_BYTES;
    reg clk=0, rst=1, serial_in=1;
    always #40 clk=~clk; // 12.5 MHz
    wire [7:0] rx_byte, tx_byte;
    wire rx_valid, tx_valid;
    wire [31:0] pc;
    uart_rx #(.CLOCK_HZ(12_500_000), .BAUD(115_200)) receiver (
        .clk(clk), .rst(rst), .rx(serial_in), .data(rx_byte), .valid(rx_valid)
    );
    rv32_soc #(.MEM_WORDS(8192), .MEM_HEX("build/firmware/mini_shell_sim.hex")) dut (
        .clk(clk), .rst(rst), .uart_tx_ready(1'b1),
        .uart_rx_data(rx_byte), .uart_rx_valid(rx_valid),
        .uart_tx_data(tx_byte), .uart_tx_valid(tx_valid), .debug_pc(pc)
    );
    reg [7:0] log_bytes [0:4095];
    reg [31:0] app_words [0:2047];
    integer count=0, prompts=0, i, j, found, match_at;
    integer app_sum=0, app_byte, k;
    reg saw_app_pc=0;

    initial $readmemh("build/firmware/hello_app.hex", app_words);
    always @(posedge clk) if(pc >= 32'h4000 && pc < 32'h6000) saw_app_pc <= 1;

    always @(posedge clk) if (tx_valid) begin
        if (count >= 4096) $fatal(1,"UART log full");
        log_bytes[count] <= tx_byte;
        count <= count+1;
        if (tx_byte == ">") prompts <= prompts+1;
    end

    task send_byte(input [7:0] b);
        integer k;
        begin
            serial_in=0; #8680;
            for(k=0;k<8;k=k+1) begin serial_in=b[k]; #8680; end
            serial_in=1; #8680;
        end
    endtask
    function [7:0] hex_char(input [3:0] nibble);
        begin hex_char = nibble < 10 ? "0" + nibble : "a" + nibble - 10; end
    endfunction
    task send_decimal(input integer number);
        integer divisor, started, digit;
        begin
            started=0;
            for(divisor=1000;divisor>=1;divisor=divisor/10) begin
                digit=(number/divisor)%10;
                if(started || digit!=0 || divisor==1) begin
                    send_byte("0"+digit);
                    started=1;
                end
            end
        end
    endtask
    task send_hex32(input integer number);
        integer shift;
        begin
            for(shift=28;shift>=0;shift=shift-4)
                send_byte(hex_char((number>>shift)&15));
        end
    endtask
    task require_text(input [8*64-1:0] s, input integer len);
        begin
            found=0;
            for(i=0;i<count-len+1;i=i+1) begin
                match_at=1;
                for(j=0;j<len;j=j+1)
                    if(log_bytes[i+j] !== s[8*(len-1-j)+:8]) match_at=0;
                if(match_at) found=1;
            end
            if(!found) begin
                $display("UART log (%0d bytes):",count);
                for(i=0;i<count;i=i+1) $write("%c",log_bytes[i]);
                $display("");
                $fatal(1,"Missing UART text");
            end
        end
    endtask

    initial begin
        #230 rst=0;
        wait(prompts >= 1);
        send_byte("w"); send_byte("r"); send_byte("i"); send_byte("t"); send_byte("e");
        send_byte(" "); send_byte("h"); send_byte("i"); send_byte("."); send_byte("t"); send_byte("x"); send_byte("t");
        send_byte(" "); send_byte("H"); send_byte("i"); send_byte(8'h0d);
        wait(prompts >= 2);
        require_text("written",7);
        if(dut.ramdisk[384][15:0] !== 16'h6948) $fatal(1,"RAM disk data mismatch");
        send_byte("c"); send_byte("a"); send_byte("t"); send_byte(" ");
        send_byte("h"); send_byte("i"); send_byte("."); send_byte("t"); send_byte("x"); send_byte("t"); send_byte(8'h0d);
        wait(prompts >= 3);
        require_text({8'h48,8'h69,8'h0d,8'h0a},4);
        send_byte("l"); send_byte("s"); send_byte(8'h0d);
        wait(prompts >= 4);
        require_text("hi.txt  2 bytes",15);
        send_byte("r"); send_byte("m"); send_byte(" ");
        send_byte("h"); send_byte("i"); send_byte("."); send_byte("t"); send_byte("x"); send_byte("t"); send_byte(8'h0d);
        wait(prompts >= 5);
        require_text("removed",7);
        if(dut.ramdisk[128][7:0] !== 0) $fatal(1,"file table entry not freed");
        for(k=0;k<APP_BYTES;k=k+1)
            app_sum=app_sum+((app_words[k>>2]>>(8*(k&3)))&255);
        send_byte("u"); send_byte("p"); send_byte("l"); send_byte("o"); send_byte("a"); send_byte("d");
        send_byte(" "); send_byte("h"); send_byte("i"); send_byte("."); send_byte("a"); send_byte("p"); send_byte("p");
        send_byte(" "); send_decimal(APP_BYTES); send_byte(" "); send_hex32(app_sum); send_byte(8'h0d);
        for(k=0;k<APP_BYTES;k=k+1) begin
            app_byte=(app_words[k>>2]>>(8*(k&3)))&255;
            send_byte(hex_char((app_byte>>4)&15));
            send_byte(hex_char(app_byte&15));
        end
        wait(prompts >= 6);
        require_text("uploaded",8);
        send_byte("r"); send_byte("u"); send_byte("n"); send_byte(" ");
        send_byte("h"); send_byte("i"); send_byte("."); send_byte("a"); send_byte("p"); send_byte("p"); send_byte(8'h0d);
        wait(prompts >= 7);
        require_text("Hello from loaded app!",22);
        require_text("returned",8);
        if(!saw_app_pc) $fatal(1,"CPU never fetched from app RAM");
        if(dut.mem[4096] !== app_words[0]) $fatal(1,"loaded app instruction mismatch");
        $display("PASS: UART RX, MiniFS upload, CPU app fetch/execute/return, shell commands");
        $finish;
    end
    initial begin #100_000_000; $fatal(1,"shell timeout, prompts=%0d",prompts); end
endmodule
`default_nettype wire
