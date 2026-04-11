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
