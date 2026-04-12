class my_transaction extends uvm_sequence_itemL 
`uvm_object_utils (my_transaction)

rand logic [7:0] data_in; 
rand int delay; 

constraint_data_c {data_in inside {[8'h00 : 8'hFF]}; }
constraint_delay_c {delay inside {[1 : 5]}; }

function new (string name = "my_transaction");
super.new(name)
endfunction 
endclass 

class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils (my_driver)

  virtual req_ack_if vif;

 // ב-UVM מקשרים את האינטרפייס בשלב ה-build_phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual req_ack_if)::get(this, "", "vif", vif))
       `uvm_fatal("NO_VIF", "Could not get interface handle")
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever begin
      seq_item_port.get_next_item(req); // מושך טרנזקציה מהסיקוונסר
      
      // הלוגיקה המקורית שלך
      @(posedge vif.clk);
      vif.data_in <= req.data_in;
      vif.req     <= 1'b1;
      
      wait(vif.ack == 1'b1);
      @(posedge vif.clk);
      vif.req     <= 1'b0;
      wait(vif.ack == 1'b0);
      
      seq_item_port.item_done(); // מודיע שסיים
    end
  endtask
endclass

    class my_monitor extends uvm_monitor;
  `uvm_component_utils(my_monitor)

  virtual req_ack_if vif;
  uvm_analysis_port #(my_transaction) item_collected_port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_port = new("item_collected_port", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    uvm_config_db#(virtual req_ack_if)::get(this, "", "vif", vif);
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_transaction trans;
    forever begin
      @(posedge vif.clk);
      if (vif.ack == 1'b1) begin
        trans = my_transaction::type_id::create("trans");
        trans.data_in = vif.internal_reg;
        
        item_collected_port.write(trans); // שליחה ל-Scoreboard
        
        wait(vif.ack == 1'b0);
      end
    end
  endtask
endclass

    class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  // FIFO לקבלת נתונים מהמוניטור
  uvm_tlm_analysis_fifo #(my_transaction) monitor_fifo;
  
  // כאן אפשר להוסיף תור (Queue) כדי לשמור את הערכים שציפינו להם מהגנרטור
  my_transaction expected_queue[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    monitor_fifo = new("monitor_fifo", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_transaction actual_trans;
    forever begin
      // מחכה שטרנזקציה תגיע מהמוניטור
      monitor_fifo.get(actual_trans);
      
      // לוגיקת השוואה (כאן אתה בודק אם ה-Data תקין)
      `uvm_info("SCB", $sformatf("Comparison: Received Data 0x%h", actual_trans.data_in), UVM_LOW)
      
      // דוגמה לבדיקה פשוטה:
      if (actual_trans.data_in === 8'hXX) begin
         `uvm_error("SCB_FAIL", "Detected undefined data!")
      end
    end
  endtask
endclass

  class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)

  my_driver    driver;
  my_monitor   monitor;
  uvm_sequencer#(my_transaction) sequencer;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    // תמיד בונים מוניטור
    monitor = my_monitor::type_id::create("monitor", this);
    
    // בונים דרייבר וסיקוונסר רק אם ה-Agent אקטיבי
    if (get_is_active() == UVM_ACTIVE) begin
      driver = my_driver::type_id::create("driver", this);
      sequencer = uvm_sequencer#(my_transaction)::type_id::create("sequencer", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass  

    class my_env extends uvm_env;
  `uvm_component_utils(my_env)

  my_agent      agent;
  my_scoreboard scoreboard;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = my_agent::type_id::create("agent", this);
    scoreboard = my_scoreboard::type_id::create("scoreboard", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    // חיבור המוניטור ל-Scoreboard דרך ה-Analysis Port
    agent.monitor.item_collected_port.connect(scoreboard.monitor_fifo.analysis_export);
  endfunction
endclass
