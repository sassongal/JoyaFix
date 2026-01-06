# מדריך פתרון בעיות - JoyaFix

## בעיה: ההמרה לא עובדת

### שלב 1: בדוק שה-Hotkey נרשם

הרץ את האפליקציה עם לוגים:

```bash
./test.sh
```

חפש את השורה:
```
✓ Global hotkey registered: ⌃⇧I
```

אם אתה רואה את המקשים שהגדרת (Ctrl+Shift+I), זה אומר שהרישום הצליח.

### שלב 2: בדוק הרשאות Accessibility

1. פתח **System Preferences**
2. עבור ל-**Security & Privacy → Privacy → Accessibility**
3. וודא ש-**JoyaFix** מסומן ✓

אם JoyaFix לא ברשימה:
- לחץ על המנעול 🔒
- לחץ + והוסף את `build/JoyaFix.app`
- סמן את התיבה

### שלב 3: בדוק שהמקש לא תפוס

הרץ:
```bash
defaults read -g NSUserKeyEquivalents
```

אם אתה רואה את Ctrl+Shift+I ברשימה, המקש כבר תפוס.

### שלב 4: נסה מקש אחר

1. לחץ על **א/A** בשורת התפריטים
2. בחר **Settings...**
3. לחץ על הכפתור עם המקש הנוכחי
4. נסה מקש אחר (למשל: Cmd+Option+L)

### שלב 5: בדוק Debug Logs

כשאתה לוחץ על המקש, אתה אמור לראות:

```
🔥 Hotkey pressed! Converting text...
Original text: ...
Converted text: ...
```

אם אתה לא רואה את זה, המקש לא מגיע לאפליקציה.

## בעיה: התפריט לא עובד

זה כבר תוקן! ה-bug היה בשורה 36 של JoyaFixApp.swift.

הפתרון:
- הסרנו `statusItem?.menu = NSMenu()` שדרס את התפריט
- התפריט עכשיו אמור לעבוד

## בדיקה מהירה

1. הרץ `./test.sh`
2. לחץ על **א/A** בשורת התפריטים
3. אתה אמור לראות:
   - No clipboard history (אם לא העתקת כלום)
   - Clear History
   - Settings...
   - Quit

אם התפריט לא מופיע, זה בעיית הרשאות.

## בדיקת ההמרה

1. פתח TextEdit
2. הקלד: `shalom`
3. בחר את הטקסט (Cmd+A)
4. לחץ על המקש שהגדרת (Ctrl+Shift+I)
5. אמור להופיע: `שלום`

## לוגים נוספים

אם אתה רוצה לראות עוד לוגים:

```bash
# הרץ את האפליקציה
./test.sh

# בטרמינל אחר, צפה בלוגים:
log stream --predicate 'process == "JoyaFix"' --level debug
```

## עזרה נוספת

אם כלום לא עובד:

1. מחק את build/
2. הרץ `./build.sh` מחדש
3. בדוק שההרשאות Accessibility ניתנו
4. נסה מקש אחר בהגדרות

---

**עדיין לא עובד?** בדוק ב-Console.app עבור שגיאות של JoyaFix.
