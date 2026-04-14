// 1. ירושה מ-uvm_monitor. שימוש בטרנזקציה כפרמטר (my_transaction)
class my_monitor extends uvm_monitor #(my_transaction);

  // רישום המחלקה ל-Factory של UVM
  `uvm_component_utils(my_monitor)

  // 2. אינטרפייס וירטואלי - גישת "קריאה בלבד" לסיגנלים
  virtual my_interface vif;

  // 3. Analysis Port - ה"צינור" שדרכו המוניטור משדר את הטרנזקציות שאסף
  uvm_analysis_port #(my_transaction) ap;

  // Constructor סטנדרטי
  function new(string name, uvm_component parent);
    super.new(name, parent);
    // יצירת ה-Analysis Port ב-Constructor
    ap = new("ap", this);
  endfunction

  // 4. ה-Run Phase: הלוגיקה הראשית של הרכיב (רץ לנצח)
  virtual task run_phase(uvm_phase phase);
    
    forever begin
      // 5. המשימה המרכזית: המתנה ודגימה של טרנזקציה בודדת
      collect_transaction();
    end
  endtask

  // Task ייעודי לאיסוף הנתונים לפי הפרוטוקול (Handshake)
  virtual task collect_transaction();
    my_transaction trans;
    
    // א. מחכים לעליית שעון כדי לדגום בצורה יציבה
    @(posedge vif.clk);

    // ב. המתנה לתנאי תחילת טרנזקציה:req וגם ack חייבים להיות ב-'1'
    // זו הנקודה שבה המידע על ה-data bus נחשב "תקף" (Valid)
    wait(vif.req == 1 && vif.ack == 1);

    // ג. יצירת אובייקט טרנזקציה חדש לאחסון הנתונים שנדגמו
    trans = my_transaction::type_id::create("trans");

    // ד. דגימת הנתונים מהאינטרפייס לתוך אובייקט הטרנזקציה (Sampling)
    // שים לב: המוניטור רק קורא את הערכים
    trans.data = vif.data;

    `uvm_info("MON", $sformatf("Observed transaction: data=0x%0h", trans.data), UVM_HIGH)

    // ה. שידור הטרנזקציה דרך ה-Analysis Port לכל מי שרשום אליו (Scoreboard)
    ap.write(trans);
    
    // ו. סנכרון סופי: מחכים לשעון הבא לפני שמתחילים לחפש את הטרנזקציה הבאה
    // זה מונע כפל דגימות של אותה טרנזקציה
    @(posedge vif.clk);
    
  endtask

endclass
