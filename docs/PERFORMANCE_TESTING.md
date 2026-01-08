# Performance Testing Guide

## שימוש ב-Xcode Instruments לבדיקות ביצועים

### שלב 1: הפעלת Instruments

1. פתח את הפרויקט ב-Xcode
2. בחר **Product → Profile** (⌘I)
3. בחר **Time Profiler** template
4. לחץ **Choose**

### שלב 2: הרצת האפליקציה

1. Instruments תריץ את האפליקציה
2. בצע פעולות שונות:
   - הפעל OCR מספר פעמים
   - השתמש ב-clipboard history
   - הפעל snippet expansion
   - פתח וסגור את Settings

### שלב 3: ניתוח תוצאות

1. **Call Tree View**:
   - בחר **View → Call Tree**
   - סמן **Invert Call Tree** ו-**Hide System Libraries**
   - חפש functions שצורכים זמן רב

2. **Heavy Stack Trace**:
   - לחץ על function חשוד
   - בדוק את ה-call stack
   - זהה bottlenecks

### שלב 4: זיהוי Bottlenecks

#### אזורים קריטיים לבדיקה:

1. **OCR Processing**:
   - `OCRService.preprocessImage()` - צריך להיות < 500ms
   - `OCRService.extractTextWithVision()` - צריך להיות < 3s
   - Image caching - צריך להאיץ בקריאות חוזרות

2. **Clipboard Monitoring**:
   - `ClipboardHistoryManager.checkForClipboardChanges()` - צריך להיות < 50ms
   - Polling interval - צריך להיות 1.0s (כבר מוגדר)

3. **Snippet Expansion**:
   - `InputMonitor.processSnippetMatch()` - צריך להיות < 100ms
   - Event tap callback - צריך להיות < 10ms

4. **Network Requests**:
   - Gemini API calls - צריך להיות < 5s
   - Retry logic - צריך להיות efficient

### שלב 5: אופטימיזציה

#### דוגמאות לתיקונים:

```swift
// לפני (איטי)
func processImage(_ image: CGImage) {
    // עיבוד כבד על main thread
    let processed = heavyProcessing(image)
}

// אחרי (מהיר)
func processImage(_ image: CGImage) {
    DispatchQueue.global(qos: .userInitiated).async {
        let processed = heavyProcessing(image)
        DispatchQueue.main.async {
            // עדכון UI
        }
    }
}
```

### כלים נוספים

#### 1. Allocations Instrument
- **שימוש**: לזיהוי memory allocations
- **הפעלה**: Product → Profile → Allocations
- **בדיקה**: חפש allocations גדולים או תכופים

#### 2. System Trace Instrument
- **שימוש**: לזיהוי thread blocking
- **הפעלה**: Product → Profile → System Trace
- **בדיקה**: חפש threads שחסומים זמן רב

#### 3. Energy Log
- **שימוש**: לזיהוי צריכת אנרגיה
- **הפעלה**: Product → Profile → Energy Log
- **בדיקה**: חפש פעולות שצורכות אנרגיה רבה

### מדדי ביצועים (Targets)

| פעולה | זמן יעד | זמן מקסימלי |
|-------|---------|-------------|
| Hotkey response | < 50ms | < 100ms |
| OCR extraction (local) | < 2s | < 3s |
| OCR extraction (cloud) | < 5s | < 10s |
| Clipboard monitoring | < 50ms | < 100ms |
| Snippet expansion | < 100ms | < 200ms |
| Image preprocessing | < 500ms | < 1s |
| Network request | < 3s | < 5s |

### בדיקות אוטומטיות

#### הוספת Performance Tests:

```swift
func testOCRPerformance() {
    let testImage = createTestImage(width: 800, height: 600)
    measure {
        let expectation = XCTestExpectation(description: "OCR")
        ocrService.extractText(from: testImage) { _ in
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 10.0)
    }
}
```

### Profiling Best Practices

1. **Profile on Real Device**: תמיד בדוק על מכשיר אמיתי, לא רק simulator
2. **Profile Release Build**: בדוק build של release, לא debug
3. **Profile Multiple Times**: הרץ מספר פעמים לקבלת ממוצע
4. **Profile Different Scenarios**: בדוק תרחישים שונים (small/large images, etc.)
5. **Compare Before/After**: השווה תוצאות לפני ואחרי אופטימיזציה

### Checklist

- [ ] OCR extraction < 3s
- [ ] Hotkey response < 100ms
- [ ] Clipboard monitoring < 100ms
- [ ] Snippet expansion < 200ms
- [ ] Image preprocessing < 1s
- [ ] Memory usage < 100MB
- [ ] CPU usage < 20% idle
- [ ] No main thread blocking
- [ ] Efficient caching
- [ ] No memory leaks

### Troubleshooting

#### בעיה: OCR איטי
**פתרון**:
- בדוק image preprocessing
- בדוק אם caching עובד
- בדוק network latency (אם cloud OCR)

#### בעיה: Hotkey response איטי
**פתרון**:
- בדוק event tap callback
- בדוק אם יש blocking operations
- בדוק thread synchronization

#### בעיה: Memory usage גבוה
**פתרון**:
- בדוק image cache size
- בדוק clipboard history limit
- בדוק memory leaks עם Leaks instrument

### כלים חיצוניים

1. **Instruments Command Line**:
   ```bash
   xcrun xctrace record --template "Time Profiler" --launch -- ./JoyaFix.app
   ```

2. **Activity Monitor**:
   - פתח Activity Monitor
   - חפש את JoyaFix
   - בדוק CPU ו-Memory usage

3. **Console.app**:
   - פתח Console.app
   - חפש logs מ-JoyaFix
   - בדוק performance logs

### דוגמאות לתיקונים

#### תיקון 1: Image Preprocessing Optimization
```swift
// לפני
func preprocessImage(_ image: CGImage) -> CGImage? {
    // עיבוד כבד על main thread
    return process(image)
}

// אחרי
func preprocessImage(_ image: CGImage) -> CGImage? {
    // בדיקת cache קודם
    if let cached = getCachedImage(key: generateKey(image)) {
        return cached
    }
    
    // עיבוד על background thread
    return processOnBackground(image)
}
```

#### תיקון 2: Clipboard Polling Optimization
```swift
// לפני
private let pollInterval: TimeInterval = 0.5

// אחרי
private let pollInterval: TimeInterval = 1.0  // פחות תכוף
private var lastClipboardHash: String?  // hash check לפני עיבוד
```

### סיכום

בדיקות ביצועים הן קריטיות לייצור. השתמש ב-Instruments באופן קבוע כדי לזהות bottlenecks ולשפר את הביצועים.

**זכור**: ביצועים טובים = חוויית משתמש טובה!

