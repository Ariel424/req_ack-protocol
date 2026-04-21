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

  function void display(string name);
    $display("[%s] Time: %0t | Data: 0x%h | Delay: %0d", name, $time, data_in, delay);
  endfunction
endclass

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
      gen2drv.put(tr.copy()); // שולחים עותק כדי למנוע דריסת נתונים
    end
    -> done;
  endtask
endclass

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
  bit timeout_reached = 0;

  $display("[DRV] Waiting for reset to start...");

  fork
    begin
      wait(vif.reset_n == 0); 
      wait(vif.reset_n == 1); 
    end

    begin
      repeat(1000) @(vif.drv_cb); 
      timeout_reached = 1;
    end
  join_any

  disable fork;

  if (timeout_reached) begin
    $fatal(1, "[DRV] FATAL ERROR: Reset Watchdog Timeout! reset_n is stuck at 0.");
  end else begin
    $display("[DRV] Reset completed successfully within time limits.");
  end

  vif.drv_cb.req <= 0;
  vif.drv_cb.data <= 0;

endtask

  task main();
    forever begin
      my_transaction tr;
      gen2drv.get(tr);
      
      // סנכרון מול השעון דרך ה-clocking block
      @(vif.drv_cb);
      vif.drv_cb.req  <= 1;
      vif.drv_cb.data <= tr.data_in;
      
      drv2sb.put(tr); // שליחה לסקורבורד לציפייה

      fork
        begin: wait_ack
          wait(vif.drv_cb.ack == 1);
        end
        begin: timeout
          repeat(100) @(vif.drv_cb);
          $error("TIMEOUT! No ACK");
        end
      join_any
      disable fork;

      repeat(tr.delay) @(vif.drv_cb);
      vif.drv_cb.req <= 0;
    end
  endtask
endclass
          
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
      if (vif.mon_cb.req && vif.mon_cb.ack) begin
        my_transaction tr = new();
        tr.data_in = vif.mon_cb.data;
        mon2sb.put(tr);
      end
    end
  endtask
endclass

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
        if (exp_queue.size() > 0) begin
          exp = exp_queue.pop_front();
          if (act.data_in == exp.data_in) begin
            $display("[SCB] MATCH! Data: %h", act.data_in);
            pass_cnt++;
          end else begin
            $error("[SCB] MISMATCH! Exp: %h, Got: %h", exp.data_in, act.data_in);
            fail_cnt++;
          end
        end
      end
    join
  endtask
endclass

class environment;
  generator      gen;
  my_driver      drv;
  my_monitor     mon;
  my_scoreboard  scb;

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
  endfunction

  module tb_top;
  bit clk;

  always #5 clk = ~clk;

  my_interface intf(clk);

  // חיבור לדיזיין (DUT)
  req_ack_with_mem dut (
    .clk(clk),
    .reset_n(intf.reset_n),
    .req(intf.req),
    .data_in(intf.data),
    .ack(intf.ack)
    // שאר הסיגנלים של ה-DUT...
  );

  environment env;

  initial begin
    intf.reset_n = 0;
    #20 intf.reset_n = 1;

    env = new(intf);
    
    fork
      env.test();
    join_none

    wait(env.gen.done);
    env.post_test();
    $finish;
  end
endmodule
