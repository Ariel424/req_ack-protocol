class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils (my_driver); 

  virtual req_ack_vif if; 

  function new (string name, uvm_component parent)
    super.new (name, parent);
  endfunction 
      
  virtual task run_phase (uvm_phase phase); 
    // reset for the system for stabilization
    driver_reset_sequence(); 

    forever begin 
      seq_item_port.get_next_item (req);
      drive_item (req);
      seq_item_port.item_done();
    end
  endtask 

  virtual task drive_reset_sequence();
    `uvm_info ("DRV", "Starting reset sequence", UVM_LOW) 
    vif.reset_n <= 0; 
    vif.req <= 0;

    repeat (5) @(posedge vif.clk);
    vif.reset_m <=1;
  endtask 

  virtual task driver_tem (my_transaction tr)
    @(posedge vif.clk);
    vif.req <=1;
    vif.data <= tr.data;

    wait (vif.ack == 1);
    repeat (tr.delay) @(posedge vif.clk);
    vif.req <= 0; 
  endtask 
endclass 

class my_sequence extends uvm_sequence #(my_transaction);
  `uvm_component_utils (my_sequence);

  rand bit [31:0] data;
  rand int delay;

  constraint delay_c {delay inside {[1:10]}; }

  function new (string name = " ");
    super.new(name); 
  endfunction 
endclass 

class my_sequencer extends uvm_sequencer #(my_transaction);  
  `uvm_component_utils (my_sequencer)

  function new (string name, uvm_component parent);
    super.new (name, parent);
  endfunction 
endclass 

class my_monitor extends uvm_monitor #(my_transaction);
  `uvm_component_utils(my_monitor)

  virtual my_interface vif;
  uvm_analysis_port #(my_transaction) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_transaction trans;

    // לופ אינסופי שרגיש גם לשעון וגם לריסט (Asynchronous Reset)
    forever @(posedge vif.clk or negedge vif.reset_n) begin
      
      if (!vif.reset_n) begin
        // לוגיקת איפוס: כאן המוניטור "מתנקה"
        `uvm_info("MON", "Reset detected - Monitoring suspended", UVM_LOW)
      end 
      
      else if (vif.req && vif.ack) begin
        // זיהוי Handshake תקין: req=1 וגם ack=1
        
        // יצירת אובייקט חדש דרך ה-Factory
        trans = my_transaction::type_id::create("trans", this);
        
        // דגימת הנתונים מה-Bus
        trans.data = vif.data;
        
        // שידור הטרנזקציה ל-Scoreboard דרך ה-Analysis Port
        ap.write(trans);
        
        `uvm_info("MON", $sformatf("Sampled Data: 0x%0h", trans.data), UVM_HIGH)
      end
    end
  endtask
endclass
    
