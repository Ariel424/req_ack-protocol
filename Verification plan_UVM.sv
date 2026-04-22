// -------------------------------------------------------------------------
// 1. Transaction: האובייקט שעובר במערכת
// -------------------------------------------------------------------------
class my_transaction #(parameter WIDTH = 8) extends uvm_sequence_item;
  
  `uvm_object_param_utils(my_transaction#(WIDTH))

  rand bit [WIDTH-1:0] data;
  rand int delay;

  constraint c_delay { delay inside {[1:10]}; }
  constraint c_data { data inside {[h'00 : h'FF]; }

  function new (string name = "my_transaction");
    super.new(name);
  endfunction

  virtual function void do_copy(uvm_object rhs);
    my_transaction#(WIDTH) rhs_;
    if (!$cast(rhs_, rhs)) begin
      `uvm_error("do_copy", "Cast failed")
      return;
    end
    
    super.do_copy(rhs); 
    this.data = rhs_.data;
    this.delay = rhs_.delay;
  endfunction
endclass

// -------------------------------------------------------------------------
// 2. Sequence & Sequencer: המוח והמרכזייה
// -------------------------------------------------------------------------
class my_base_sequence extends uvm_sequence #(my_transaction);
  `uvm_object_utils(my_base_sequence)

  function new (string name = "my_base_sequence");
  super.new(name); 
  endfunction

  virtual task body();
    if (starting_phase != null) starting_phase.raise_objection(this);
    repeat(10) begin
      req = my_transaction::type_id::create("req");
      start_item(req);
      if (!req.randomize()) `uvm_fatal("SEQ", "Randomization failed!")
      finish_item(req);
    end
    if (starting_phase != null) starting_phase.drop_objection(this);
  endtask
endclass

class my_sequencer extends uvm_sequencer #(my_transaction);
  `uvm_component_utils(my_sequencer)
  function new(string name, uvm_component parent); 
  super.new(name, parent); 
  endfunction
endclass

// -------------------------------------------------------------------------
// 3. Driver: המתרגם לחומרה (Active)
// -------------------------------------------------------------------------
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  
  virtual my_interface vif;
  uvm_analysis_port #(my_transaction) drv_ap; // לשליחת הציפייה לסקורבורד

  function new(string name, uvm_component parent);
  super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual my_interface)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get vif from config_db")
    drv_ap = uvm_analysis_port #(my_transaction)::type_id::create("drv_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    // Reset Sequence
    vif.reset_n <= 0;
    vif.req     <= 0;
    repeat(5) @(posedge vif.clk);
    vif.reset_n <= 1;

    forever begin
      seq_item_port.get_next_item(req);
      drv_ap.write(req); // מדווח לסקורבורד מה הולך להישלח
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

virtual task drive_item(my_transaction tr);
    @(posedge vif.clk);
    vif.req  <= 1;
    vif.data <= tr.data;

    fork
        begin: wait_for_ack
            wait(vif.ack == 1);
        end
        begin: timeout_watchdog
            repeat(100) @(posedge vif.clk); // מחכים מקסימום 100 שעונים
            `uvm_error("DRV_TIMEOUT", "DUT failed to respond with ACK within 100 cycles!")
        end
    join_any
    disable fork; // עוצר את התהליך שעדיין רץ (או ה-wait או ה-timeout)

    repeat(tr.delay) @(posedge vif.clk);
    vif.req  <= 0;
  endtask
endclass 

// -------------------------------------------------------------------------
// 4. Monitor: הצופה הפסיבי
// -------------------------------------------------------------------------
class my_monitor extends uvm_monitor;
  `uvm_component_utils(my_monitor)
  virtual my_interface vif;
  uvm_analysis_port #(my_transaction) mon_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual my_interface)::get(this, "", "vif", vif))
      `uvm_fatal("MON", "Could not get vif from config_db")
    mon_ap = new("mon_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever @(posedge vif.clk or negedge vif.reset_n) begin
      if (!vif.reset_n) begin
        `uvm_info("MON", "Reset detected, clearing monitor state", UVM_HIGH)
      end     
      else if (vif.req && vif.ack) begin
        my_transaction tr = my_transaction::type_id::create("tr");
        tr.data = vif.data;
        mon_ap.write(tr);
        `uvm_info("MON", $sformatf("Sampled Data: %0h", tr.data), UVM_MEDIUM)
      end
    end
  endtask
endclass
      
// -------------------------------------------------------------------------
// 5. Scoreboard: השופט (משתמש ב-Decl Macros להפרדת כניסות)
// -------------------------------------------------------------------------
`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  uvm_analysis_imp_exp #(my_transaction, my_scoreboard) exp_imp;
  uvm_analysis_imp_act #(my_transaction, my_scoreboard) act_imp;
  my_transaction exp_queue[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase (uvm_phase phase)
    super.build_phase (phase)
    exp_imp = new("exp_imp", this);
    act_imp = new("act_imp", this);
  endfunction

  // מגיע מהדרייבר
  function void write_exp(my_transaction tr);
    exp_queue.push_back(tr);
  endfunction

  // מגיע מהמוניטור
  function void write_act(my_transaction tr);
    if(exp_queue.size() > 0) begin
      my_transaction exp = exp_queue.pop_front();
      if(tr.data == exp.data)
        `uvm_info("SB", $sformatf("MATCH! Data: %0h", tr.data), UVM_LOW)
      else
        `uvm_error("SB", $sformatf("MISMATCH! Exp: %0h, Got: %0h", exp.data, tr.data))
    end else begin
        `uvm_error("SB", "Received unexpected data (Queue empty)")
    end
  endfunction
endclass

// -------------------------------------------------------------------------
// 6. Agent & Env: התשתית
// -------------------------------------------------------------------------
class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)
  my_driver drv;
  my_monitor mon;
  my_sequencer seqr;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    mon = my_monitor::type_id::create("mon", this);
    if(get_is_active() == UVM_ACTIVE) begin
      drv = my_driver::type_id::create("drv", this);
      seqr = my_sequencer::type_id::create("seqr", this);
    end
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    if(get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass

class my_env extends uvm_env;
  `uvm_component_utils(my_env)
  my_agent agent;
  my_scoreboard sb;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    agent = my_agent::type_id::create("agent", this);
    sb = my_scoreboard::type_id::create("sb", this);
  endfunction

  virtual function void connect_phase(uvm_phase phase);
    agent.drv.drv_ap.connect(sb.exp_imp); // ציפיות מהדרייבר
    agent.mon.mon_ap.connect(sb.act_imp); // תוצאות מהמוניטור
  endfunction
endclass

// -------------------------------------------------------------------------
// 7. Test: הניהול העליון
// -------------------------------------------------------------------------
class my_test extends uvm_test;
  `uvm_component_utils(my_test)
  my_env env;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    env = my_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_base_sequence seq = my_base_sequence::type_id::create("seq");
    phase.raise_objection(this);
    seq.start(env.agent.seqr);
    #100ns; // זמן המתנה לעיבוד הטרנזקציות האחרונות
    phase.drop_objection(this);
  endtask
endclass
