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
  transaction trans;
  mailbox gen2drv;
  virtual req_ack_if vif;

  
  function new(mailbox gen2drv);
    this.gen2drv = gen2drv;
  endfunction
