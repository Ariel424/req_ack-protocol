class my_monitor_sv;
  
  virtual my_interface vif;
  // Mailbox משמש כאן כתחליף ל-Analysis Port של UVM
  mailbox #(my_transaction) mon2sb_mbx;

  function new(virtual my_interface vif, mailbox #(my_transaction) mbx);
    this.vif = vif;
    this.mon2sb_mbx = mbx;
  endfunction

  // ב-SV אין run_phase, אז נגדיר Task ריצה עצמאי
  virtual task run();
    my_transaction trans;

    forever @(posedge vif.clk or negedge vif.reset_n) begin
      
      if (!vif.reset_n) begin
        // לוגיקת איפוס ב-SV
        $display("[MON_SV] Reset detected at %0t", $time);
      end 
      
      else if (vif.req && vif.ack) begin
        // דגימת הנתונים ב-SV
        trans = new(); // ב-SV רגיל יוצרים אובייקט עם new
        trans.data = vif.data;
        
        // שליחת האובייקט ל-Mailbox (פעולה חוסמת ב-SV)
        mon2sb_mbx.put(trans);
        
        $display("[MON_SV] Sampled Data: 0x%0h", trans.data);
      end
    end
  endtask
endclass
