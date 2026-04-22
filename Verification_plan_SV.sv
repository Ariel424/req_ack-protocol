// --- Transaction Class ---
class my_transaction;
  rand logic [7:0] data_in;
  rand int delay;

  constraint data_c  { data_in inside {[8'h00 : 8'hFF]}; }
  constraint delay_c { delay inside {[1 : 10]}; }

  function my_transaction copy();
    my_transaction tr;
    tr = new();
    tr.data_in = this.data_in;
    tr.delay   = this.delay;
    return tr;
  endfunction
endclass

// --- Generator ---
class generator;
  mailbox #(my_transaction) gen2drv;
  int repeat_count = 10;
  event done;

  function new(mailbox #(my_transaction) gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task main();
    repeat(repeat_count) begin
      my_transaction tr = new();
      if (!tr.randomize()) $fatal("Gen randomization failed");
      gen2drv.put(tr.copy()); 
    end
    $display("[GEN] Generated %0d transactions", repeat_count);
    -> done;
  endtask
endclass
  
// --- Driver ---
class my_driver;
  virtual my_interface.DRIVER_MP vif;
  mailbox #(my_transaction) gen2drv;
  mailbox #(my_transaction) drv2sb; 

  function new(virtual my_interface.DRIVER_MP vif, mailbox #(my_transaction) gen2drv, mailbox #(my_transaction) drv2sb);
    this.vif = vif;
    this.gen2drv = gen2drv;
    this.drv2sb = drv2sb;
  endfunction

  task reset();
    $display("[DRV] Resetting DUT...");
    fork
      begin
        wait(vif.reset_n == 0); 
        wait(vif.reset_n == 1); 
      end
      begin
        repeat(1000) @(vif.drv_cb);
        $fatal(1, "[DRV] Reset Timeout!");
      end
    join_any
    disable fork;
    vif.drv_cb.req <= 0;
    vif.drv_cb.data <= 0;
  endtask

  task main();
    forever begin
      my_transaction tr;
      gen2drv.get(tr);
      
      @(vif.drv_cb);
      vif.drv_cb.req  <= 1;
      vif.drv_cb.data <= tr.data_in; 
      drv2sb.put(tr); 
      fork
        begin: wait_ack
          wait(vif.drv_cb.ack == 1);
        end
        begin: timeout
          repeat(100) @(vif.drv_cb);
          $error("[DRV] TIMEOUT! No ACK from DUT");
        end
      join_any
      disable fork;

      repeat(tr.delay) @(vif.drv_cb);
      vif.drv_cb.req <= 0;
    end
  endtask
endclass

// --- Monitor ---
class my_monitor;
  virtual my_interface.MONITOR_MP vif;
  mailbox #(my_transaction) mon2sb;

  function new(virtual my_interface.MONITOR_MP vif, mailbox #(my_transaction) mon2sb);
    this.vif = vif;
    this.mon2sb = mon2sb;
  endfunction

  task main();
    forever begin
      @(vif.mon_cb);
      // דוגמים רק כשיש Valid Handshake
      if (vif.mon_cb.req && vif.mon_cb.ack) begin
        my_transaction tr = new(); // יוצרים אובייקט רק כשצריך
        tr.data_in = vif.mon_cb.data;
        mon2sb.put(tr);
      end
    end
  endtask
endclass

// --- Scoreboard ---
class my_scoreboard;
  mailbox #(my_transaction) drv2sb;
  mailbox #(my_transaction) mon2sb;
  my_transaction exp_queue[$];
  int pass_cnt, fail_cnt;

  function new(mailbox #(my_transaction) drv2sb, mailbox #(my_transaction) mon2sb);
    this.drv2sb = drv2sb;
    this.mon2sb = mon2sb;
  endfunction

  task main();
    fork
      forever begin
        my_transaction tr;
        drv2sb.get(tr);
        exp_queue.push_back(tr);
      end
      forever begin
        my_transaction act, exp;
        mon2sb.get(act);
        wait(exp_queue.size() > 0);
        exp = exp_queue.pop_front();
        
        if (act.data_in == exp.data_in) begin
          $display("[SCB] MATCH! Data: %h", act.data_in);
          pass_cnt++;
        end else begin
          $error("[SCB] MISMATCH! Exp: %h, Got: %h", exp.data_in, act.data_in);
          fail_cnt++;
        end
      end
    join
  endtask
endclass

// --- Environment ---
class environment;
  generator      gen;
  my_driver      drv;
  my_monitor     mon;
  my_scoreboard  scb;
  my_coverage    cov; 

  mailbox #(my_transaction) gen2drv;
  mailbox #(my_transaction) drv2sb;
  mailbox #(my_transaction) mon2sb;

  virtual my_interface vif;

  function new(virtual my_interface vif);
    this.vif = vif;
    gen2drv = new();
    drv2sb  = new();
    mon2sb  = new();

    gen = new(gen2drv);
    drv = new(vif.DRIVER_MP,  gen2drv, drv2sb);
    mon = new(vif.MONITOR_MP, mon2sb);
    scb = new(drv2sb, mon2sb);
    cov = new(); 
  endfunction

  task test();
    fork
      drv.main();
      mon.main();
      scb.main();
      
      forever begin
        my_transaction tr;
        mon2sb.peek(tr); 
        cov.sample(tr);
        @(vif.MONITOR_MP.mon_cb); 
      end
    join_none

    drv.reset();
    gen.main();

    wait(gen.done);
    repeat(50) @(vif.DRIVER_MP.drv_cb);
    
    $display("Coverage: %0.2f%%", cov.cg.get_inst_coverage());
    $display("Final Result: PASS=%0d, FAIL=%0d", scb.pass_cnt, scb.fail_cnt);
  endtask
endclass

// --- Top Module ---
module tb_top;
  bit clk;
  always #5 clk = ~clk;

  my_interface intf(clk);
  
  // דוגמה לחיבור DUT (יש לוודא שמות פורטים תואמים)
  // dut_top u_dut (.clk(clk), .reset_n(intf.reset_n), ...);

  environment env;

  initial begin
    intf.reset_n <= 0;
    #20 intf.reset_n <= 1;

    env = new(intf);
    env.test();
    
    $finish;
  end
endmodule

        class my_coverage;
  my_transaction tr;

  // הגדרת ה-Covergroup
  covergroup cg;
    option.per_instance = 1;

    // דגימת נתוני הכניסה (Data In) - מחלקים ל-Bins (טווחים)
    cp_data: coverpoint tr.data_in {
      bins low    = {[8'h00 : 8'h3F]};
      bins mid    = {[8'h40 : 8'hBF]};
      bins high   = {[8'hC0 : 8'hFF]};
      bins zero   = {8'h00};
      bins max    = {8'hFF};
    }

    // דגימת השיהוי (Delay)
    cp_delay: coverpoint tr.delay {
      bins short  = {[1:3]};
      bins med    = {[4:7]};
      bins long   = {[8:10]};
    }
    
    // Cross Coverage - האם בדקנו דאטה גבוה עם דיליי קצר?
    cross_data_delay: cross cp_data, cp_delay;
  endgroup

  function new();
    cg = new();
  endfunction

  // פונקציה שנקראת מה-Environment כדי לדגום
  function void sample(my_transaction tr);
    this.tr = tr;
    cg.sample();
  endfunction
endclass

class my_coverage;
  my_transaction tr;

  // הגדרת ה-Covergroup
  covergroup cg;
    option.per_instance = 1;

    // דגימת נתוני הכניסה (Data In) - מחלקים ל-Bins (טווחים)
    cp_data: coverpoint tr.data_in {
      bins low    = {[8'h00 : 8'h3F]};
      bins mid    = {[8'h40 : 8'hBF]};
      bins high   = {[8'hC0 : 8'hFF]};
      bins zero   = {8'h00};
      bins max    = {8'hFF};
    }

    // דגימת השיהוי (Delay)
    cp_delay: coverpoint tr.delay {
      bins short  = {[1:3]};
      bins med    = {[4:7]};
      bins long   = {[8:10]};
    }
    
    // Cross Coverage - האם בדקנו דאטה גבוה עם דיליי קצר?
    cross_data_delay: cross cp_data, cp_delay;
  endgroup

  function new();
    cg = new();
  endfunction

  // פונקציה שנקראת מה-Environment כדי לדגום
  function void sample(my_transaction tr);
    this.tr = tr;
    cg.sample();
  endfunction
endclass
