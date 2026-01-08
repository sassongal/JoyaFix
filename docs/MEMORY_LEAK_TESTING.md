# Memory Leak Testing Guide

## שימוש ב-Xcode Instruments לזיהוי Memory Leaks

### שלב 1: הפעלת Instruments

1. פתח את הפרויקט ב-Xcode
2. בחר **Product → Profile** (⌘I)
3. בחר **Leaks** template
4. לחץ **Choose**

### שלב 2: הרצת האפליקציה

1. Instruments תריץ את האפליקציה
2. בצע פעולות שונות:
   - הפעל OCR מספר פעמים
   - פתח וסגור את Settings
   - השתמש ב-clipboard history
   - הפעל snippet expansion
   - נעל ופתח את המקלדת

### שלב 3: זיהוי Memory Leaks

1. חפש אזהרות אדומות ב-Leaks timeline
2. לחץ על leak כדי לראות את ה-call stack
3. בדוק את ה-Object Graph:
   - בחר **View → Object Graph**
   - חפש retain cycles

### שלב 4: בדיקת Retain Cycles

1. בחר **Allocations** instrument
2. חפש אובייקטים שלא משתחררים
3. בדוק את ה-Reference Graph:
   - לחץ ימין על אובייקט חשוד
   - בחר **Show in Object Graph**

### אזורים קריטיים לבדיקה

#### 1. ScreenCaptureManager
- בדוק ש-`escapeKeyMonitor` משתחרר
- בדוק ש-`escapeKeyLocalMonitor` משתחרר
- בדוק ש-`globalMouseMonitor` משתחרר
- בדוק ש-`overlayWindows` משתחררים

#### 2. InputMonitor
- בדוק ש-`runLoopSource` משתחרר
- בדוק ש-`eventTap` משתחרר
- בדוק שאין retain cycles ב-callbacks

#### 3. ClipboardHistoryManager
- בדוק ש-`pollTimer` משתחרר
- בדוק ש-`cleanupTimer` משתחרר
- בדוק שאין memory leaks ב-file operations

#### 4. OCRService
- בדוק ש-`imageCache` לא גדל ללא גבול
- בדוק ש-CIContext משתחרר כראוי

### תיקון Memory Leaks

1. **Weak References**: השתמש ב-`[weak self]` ב-closures
2. **Deinit**: ודא ש-deinit נקרא
3. **Cleanup**: נקה resources ב-deinit
4. **Timers**: בטל timers ב-deinit

### דוגמה לתיקון

```swift
// לפני (בעייתי)
class MyClass {
    var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.doSomething()  // Retain cycle!
        }
    }
}

// אחרי (מתוקן)
class MyClass {
    var timer: Timer?
    
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.doSomething()  // No retain cycle
        }
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
}
```

### כלים נוספים

1. **Malloc Stack**: לזיהוי memory allocations
2. **Time Profiler**: לזיהוי performance bottlenecks
3. **Allocations**: לזיהוי memory growth

### Checklist

- [ ] אין memory leaks ב-Leaks instrument
- [ ] כל ה-timers מתבטלים
- [ ] כל ה-monitors מוסרים
- [ ] כל ה-callbacks משתמשים ב-weak references
- [ ] כל ה-resources משתחררים ב-deinit

