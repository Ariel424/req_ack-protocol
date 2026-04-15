class my_transaction extends uvm_sequence_item;
  `uvm_object_utils(my_transaction)

  rand bit [31:0] data;
  rand int delay;

  constraint delay_c { delay inside {[1:10]}; }

  function new(string name = ""); super.new(name); endfunction
endclass

// --- DRIVER ---
class my_driver extends uvm_driver #(my_transaction);
  `uvm_component_utils(my_driver)
  virtual my_interface vif;
  uvm_analysis_port #(my_transaction) drv_ap; // פורט לשליחת ציפיות לסקורבורד

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  virtual function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if(!uvm_config_db#(virtual my_interface)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Could not get vif")
    drv_ap = new("drv_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    drive_reset_sequence();
    forever begin
      seq_item_port.get_next_item(req);
      drv_ap.write(req); // מדווח לסקורבורד מה נשלח
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask

  task drive_reset_sequence();
    vif.reset_n <= 0;
    vif.req <= 0;
    repeat(5) @(posedge vif.clk);
    vif.reset_n <= 1;
  endtask

  task drive_item(my_transaction tr);
    @(posedge vif.clk);
    vif.req <= 1;
    vif.data <= tr.data;
    wait(vif.ack == 1);
    repeat(tr.delay) @(posedge vif.clk);
    vif.req <= 0;
  endtask
endclass

// --- MONITOR ---
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
      `uvm_fatal("MON", "Could not get vif")
    mon_ap = new("mon_ap", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    forever @(posedge vif.clk) begin
      if (vif.reset_n && vif.req && vif.ack) begin
        my_transaction tr = my_transaction::type_id::create("tr");
        tr.data = vif.data;
        mon_ap.write(tr);
      end
    end
  endtask
endclass

`uvm_analysis_imp_decl(_exp)
`uvm_analysis_imp_decl(_act)

class my_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(my_scoreboard)

  uvm_analysis_imp_exp #(my_transaction, my_scoreboard) exp_imp;
  uvm_analysis_imp_act #(my_transaction, my_scoreboard) act_imp;
  my_transaction exp_queue[$];

  function new(string name, uvm_component parent);
    super.new(name, parent);
    exp_imp = new("exp_imp", this);
    act_imp = new("act_imp", this);
  endfunction

  // מקבל ציפיות מהדרייבר
  function void write_exp(my_transaction tr);
    exp_queue.push_back(tr);
  endfunction

  // מקבל תוצאות מהמוניטור ומשווה
  function void write_act(my_transaction tr);
    if(exp_queue.size() > 0) begin
      my_transaction exp = exp_queue.pop_front();
      if(tr.data == exp.data)
        `uvm_info("SB", $sformatf("PASS: Data %0h matched", tr.data), UVM_LOW)
      else
        `uvm_error("SB", $sformatf("FAIL: Exp %0h, Got %0h", exp.data, tr.data))
    end
  endfunction
endclass

class my_agent extends uvm_agent;
  `uvm_component_utils(my_agent)
  my_driver drv;
  my_monitor mon;
  uvm_sequencer#(my_transaction) seqr;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    mon = my_monitor::type_id::create("mon", this);
    if(get_is_active() == UVM_ACTIVE) begin
      drv = my_driver::type_id::create("drv", this);
      seqr = uvm_sequencer#(my_transaction)::type_id::create("seqr", this);
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
    agent.drv.drv_ap.connect(sb.exp_imp); // חיבור דרייבר לסקורבורד (ציפיות)
    agent.mon.mon_ap.connect(sb.act_imp); // חיבור מוניטור לסקורבורד (תוצאות)
  endfunction
endclass

      class my_test extends uvm_test;
  `uvm_component_utils(my_test)
  my_env env;

  function new(string name, uvm_component parent); super.new(name, parent); endfunction

  virtual function void build_phase(uvm_phase phase);
    env = my_env::type_id::create("env", this);
  endfunction

  virtual task run_phase(uvm_phase phase);
    my_base_sequence seq = my_base_sequence::type_id::create("seq");
    phase.raise_objection(this); // מונע מהטסט להיגמר מוקדם מדי
    seq.start(env.agent.seqr);
    #100ns; // זמן המתנה קצר לסיום העיבוד
    phase.drop_objection(this);
  endtask
endclass

      
