class my_transaction extends uvm_sequence_item;
  `uvm_object_utils(my_transaction)

  rand bit [31:0] data;
  rand int delay; // משתנה לשליטה בתזמון בין בקשות

  // אילוץ: הדיליי יהיה בין 1 ל-10 מחזורי שעון
  constraint delay_c { delay inside {[1:10]}; }

  function new(string name = ""); super.new(name); endfunction
endclass

class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  virtual my_interface vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    // ביצוע ה-Reset כפי שהוגדר במטלה
    drive_reset_sequence(); 

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  virtual task drive_reset_sequence();
    vif.reset_n <= 0;
    vif.req     <= 0;
    repeat(5) @(posedge vif.clk);
    vif.reset_n <= 1;
  endtask

  virtual task drive_item(my_transaction tr);
    @(posedge vif.clk);
    vif.req  <= 1;
    vif.data <= tr.data;

    // המתנה ל-Ack (ה-Handshake)
    wait(vif.ack == 1);
    
    // הוספת השיהוי המבוקש בין בקשות
    repeat(tr.delay) @(posedge vif.clk);
    
    vif.req <= 0;
  endtask
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
    // רגישות לריסט א-סינכרוני
    forever @(posedge vif.clk or negedge vif.reset_n) begin
      if (!vif.reset_n) begin
        // לוגיקת איפוס המוניטור
      end else if (vif.req && vif.ack) begin
        trans = my_transaction::type_id::create("trans", this);
        trans.data = vif.data;
        ap.write(trans); // שליחה לסקורבורד
      end
    end
  endtask
endclass

// Sequencer
class my_sequencer extends uvm_sequencer #(my_transaction);
  `uvm_component_utils(my_sequencer)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
endclass

// Sequence
class my_base_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_base_sequence)
  
  virtual task body();
    repeat(10) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      assert(req.randomize());
      finish_item(req);
    end
  endtask
endclass

class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)
  uvm_analysis_imp #(my_transaction, my_scoreboard) item_collected_export;
  
  my_transaction exp_queue[$]; // מבנה נתונים לאחסון הציפיות

  function new(string name, uvm_component parent);
    super.new(name, parent);
    item_collected_export = new("item_collected_export", this);
  endfunction

  virtual function void write(my_transaction tr);
    // לוגיקת השוואה (Comparison Logic)
    `uvm_info("SB", $sformatf("Verified data: %0h", tr.data), UVM_LOW)
  endfunction
endclass

// Agent
class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)
  my_driver    driver;
  my_sequencer sequencer;
  my_monitor   monitor;

  virtual function void build_phase(uvm_phase phase);
    monitor = my_monitor::type_id::create("monitor", this);
    if (get_is_active() == UVM_ACTIVE) begin // בדיקת Active/Passive
      driver = my_driver::type_id::create("driver", this);
      sequencer = my_sequencer::type_id::create("sequencer", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    if (get_is_active() == UVM_ACTIVE) begin
      driver.seq_item_port.connect(sequencer.seq_item_export);
    end
  endfunction
endclass

// Environment
class my_env extends uvm_env;
  `uvm_component_utils(my_env)
  my_agent      agent;
  my_scoreboard scoreboard;

  virtual function void build_phase(uvm_phase phase);
    agent = my_agent::type_id::create("agent", this);
    scoreboard = my_scoreboard::type_id::create("scoreboard", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    // חיבור המוניטור לסקורבורד
    agent.monitor.ap.connect(scoreboard.item_collected_export);
  endfunction
endclass
