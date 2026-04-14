// 1. הגדרת המחלקה ב-SV. אין ירושה מ-uvm_monitor, זו מחלקה עצמאית לגמרי.
class my_monitor_sv;

  // 2. אינטרפייס וירטואלי - אותו מושג בדיוק כמו ב-UVM.
  virtual my_interface vif;

  // 3. הדמיית Analysis Port: משתמשים ב-Mailbox של SV להעברת נתונים.
  // ה-Scoreboard יצטרך לקבל את ה-Mailbox הזה ולקרוא ממנו.
  mailbox #(my_transaction) mon2sb_mbx;

  // 4. Constructor - פונקציה לבניית האובייקט בזיכרון.
  // מקבלת את ה-Interface וה-Mailbox (במקום דרך uvm_config_db).
  function new(virtual my_interface vif, mailbox #(my_transaction) mon2sb_mbx);
    this.vif = vif;
    this.mon2sb_mbx = mon2sb_mbx;
  endfunction

  // 5. הדמיית ה-Run Phase: ב-SV אין Phase-ים. 
  // אנחנו משתמשים ב-Task ראשי שרץ בלופ אינסופי.
  virtual task run();
    
    forever begin
      // 6. המשימה המרכזית: המתנה ודגימה של טרנזקציה בודדת (אותה לוגיקה).
      collect_transaction();
    end
  endtask

  // Task ייעודי לאיסוף הנתונים לפי הפרוטוקול (Handshake) - זהה ל-UVM.
  virtual task collect_transaction();
    my_transaction trans;
    
    // א. מחכים לעליית שעון כדי לדגום בצורה יציבה.
    @(posedge vif.clk);

    // ב. המתנה לתנאי תחילת טרנזקציה: req וגם ack חייבים להיות ב-'1'.
    wait(vif.req == 1 && vif.ack == 1);

    // ג. יצירת אובייקט טרנזקציה חדש (ב-SV משתמשים ב-new()).
    trans = new();

    // ד. דגימת הנתונים מהאינטרפייס לתוך אובייקט הטרנזקציה (Sampling).
    trans.data = vif.data;

    // הדפסת הודעת Debug (ב-SV משתמשים ב-$display).
    $display("[MON_SV] observed transaction: data=0x%0h", trans.data);

    // ה. שידור הטרנזקציה: במקום Analysis Port, כותבים ל-Mailbox.
    mon2sb_mbx.put(trans);
    
    // ו. סנכרון סופי: מחכים לשעון הבא לפני שמתחילים לחפש את הטרנזקציה הבאה.
    @(posedge vif.clk);
    
  endtask

  // כדי להפעיל את המוניטור הזה, נצטרך לכתוב ב-Main Test:
  // initial begin
  //   monitor_sv = new(vif, mbx);
  //   fork
  //     monitor_sv.run(); // מפעיל את ה-Forever loop במקביל
  //   join_none
  // end

endclass
