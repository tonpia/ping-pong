module cocotb_iverilog_dump();
initial begin
    string dumpfile_path;    if ($value$plusargs("dumpfile_path=%s", dumpfile_path)) begin
        $dumpfile(dumpfile_path);
    end else begin
        $dumpfile("C:\\Documents\\uni\\term_4\\HW_project\\testbench\\sim_build\\ov7670_capture.fst");
    end
    $dumpvars(0, ov7670_capture);
end
endmodule
