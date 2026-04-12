class transaction 

rand logic [7:0] data_in; 
rand int delay; // paramer for delay;

constraint data_c {data_in inside {[8'h00 : 9'hFF]}; }
constraint delay_c {delay inside {[1 : 5]}; } 

function transaction copy();
copy = new(); // memory access 
copy.data_in = this.data_in;
copy.delay = this.delay 
endfunction 

// פונקציית הדפסה לדיבאג
  function void display(string name);
    $display("[%s] Time: %0t | Data: 0x%h | Delay: %0d", name, $time, data_in, delay);
  endfunction
endclass

class generator;
  transaction trans;
  mailbox gen2drv; // ה"צינור" שמעביר את המידע לדרייבר

  function new(mailbox gen2drv);
    this.gen2drv = gen2drv;
  endfunction

  task main();
    repeat(32) begin // לופ שממלא את כל הזיכרון שלך
      trans = new();
      if (!trans.randomize()) $fatal("Randomization failed");
      gen2drv.put(trans); // שולח את החבילה לדרייבר
      trans.display("Generator");
    end
  endtask
endclass

class driver
  transaction trans; // object 
  mailbox gen2drv; // getting the data from the transaction 
  virtual req_ack_if vif; // connecting to the interface 

  function new (mailbox gen2drv, virtual req_ack_if vif); 
    this.gen2drv = gen2drv;
    this.vif = vif;
  endfunction

  task main (); 
    forever begin 
      gen2drv.get(trans);
      $display ("[Driver] Received Transaction: Data = 0x%h", trans.data_in);
      @(posedge vif.clk); // waiting for one clock 
      vif.data_in <= trans.data_in; // השמת הדאטה בקו
      vif.req <= 1'b1; // הרמת בקשה
      wait (vif.ack == 1'b1);
      @(posedge vif.clk); // waiting for another clocking 
      vif.req <= 1'b0; 
      wait (vif.ack == 1'b0);
      $display ("Driver]: Transaction Finished successfully");
    end
  endtask 
endclass 

class monitor 
transaction trans; // object 
mailbox mon2scb; // getting the data from the transaction 
virtual req_ack_if vif; // connecting to the interface 

function new (mailbox mon2scb, virtual req_ack_if vif);
this.mon2scb = mon2scb;
this.vif = vif;
endfunction 

task main (); 
  forever begin
    mon2scb.get(trans);
    

      

      

      
      
