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
