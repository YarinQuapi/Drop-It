class Copy {
  const Copy(this.lang);
  final String lang;
  bool get he => lang == 'he';

  String pick(String en, String he) => this.he ? he : en;

  String get appName => 'Drop It';
  String get login => pick('Log in', 'התחברות');
  String get signup => pick('Sign up', 'הרשמה');
  String get continueWithApple =>
      pick('Continue with Apple', 'המשך באמצעות Apple');
  String get orDivider => pick('or', 'או');
  String get email => pick('Email', 'אימייל');
  String get password => pick('Password', 'סיסמה');
  String get confirmPassword => pick('Confirm password', 'אימות סיסמה');
  String get changePassword => pick('Change password', 'שינוי סיסמה');
  String get currentPassword => pick('Current password', 'סיסמה נוכחית');
  String get newPassword => pick('New password', 'סיסמה חדשה');
  String get passwordChanged => pick('Password updated.', 'הסיסמה עודכנה.');
  String get passwordRulesTitle =>
      pick('Password requirements', 'דרישות סיסמה');
  String get ruleLength => pick('At least 8 characters', 'לפחות 8 תווים');
  String get ruleEnglish => pick(
    'English characters only (no spaces)',
    'תווים באנגלית בלבד (ללא רווחים)',
  );
  String get ruleUppercase => pick(
    'At least 1 uppercase letter (A-Z)',
    'לפחות אות גדולה אחת באנגלית (A-Z)',
  );
  String get ruleNumber =>
      pick('At least 1 number (0-9)', 'לפחות ספרה אחת (0-9)');
  String get ruleSymbol =>
      pick('At least 1 symbol (!@#\$...)', 'לפחות תו מיוחד אחד (!@#\$...)');
  String get ruleMatch => pick('Passwords match', 'הסיסמאות תואמות');
  String get appearance => pick('Appearance', 'מראה');
  String get themeSystem => pick('System', 'מערכת');
  String get themeLight => pick('Light', 'בהיר');
  String get themeDark => pick('Dark', 'כהה');
  String get permissions => pick('Permissions', 'הרשאות');
  String get permissionsDesc => pick(
    'Control which operations regular users are allowed to perform.',
    'שליטה בפעולות שמשתמשים רגילים רשאים לבצע.',
  );
  String get today => pick('Today', 'היום');
  String get week => pick('Week', 'השבוע');
  String get weight => pick('Weight', 'משקל');
  String get settings => pick('Settings', 'הגדרות');
  String get logout => pick('Log out', 'יציאה');
  String get fastingQuestion => pick(
    'Do you want to use intermittent fasting?',
    'האם להשתמש בצום לסירוגין?',
  );
  String get yes => pick('Yes', 'כן');
  String get no => pick('No', 'לא');
  String get continueLabel => pick('Continue', 'המשך');
  String get fastingLength => pick('Fasting length', 'משך הצום');
  String get startHour => pick('Hour to start the fast', 'שעה להתחלת הצום');
  String get endHour =>
      pick('Approximate hour to end the fast', 'שעה משוערת לסיום הצום');
  String get hours => pick('hours', 'שעות');
  String get profileTitle => pick('Your body stats', 'נתוני הגוף');
  String get sex => pick('Sex', 'מין');
  String get male => pick('Male', 'זכר');
  String get female => pick('Female', 'נקבה');
  String get dateOfBirth => pick('Date of birth', 'תאריך לידה');
  String get done => pick('Done', 'סיום');
  String get height => pick('Height (cm)', 'גובה (ס״מ)');
  String get weightKg => pick('Weight (kg)', 'משקל (ק״ג)');
  String get activity => pick('Activity', 'פעילות');
  String get pace => pick('Weekly pace', 'קצב שבועי');
  String get dailyGoal => pick('Daily calories (kcal)', 'קלוריות ליום');
  String get useSuggested => pick('Use suggested', 'השתמש בהצעה');
  String get goalFloorNote => pick(
    'Goals never go below your resting metabolism or 1,200 kcal (women) / 1,500 kcal (men).',
    'היעד לא יורד מתחת לקצב חילוף החומרים במנוחה או 1,200 קק״ל (נשים) / 1,500 קק״ל (גברים).',
  );
  String get save => pick('Save', 'שמירה');
  String get goal => pick('Calorie goal', 'יעד קלוריות');
  String get eaten => pick('Eaten', 'נאכל');
  String get remaining => pick('Remaining', 'נותר');
  String get estimate =>
      pick('Estimated from your body stats.', 'אומדן לפי נתוני הגוף שלכם.');
  String get appleHealth => 'Apple Health';
  String get healthSteps => pick('Steps', 'צעדים');
  String get healthExercise => pick('Exercise', 'פעילות גופנית');
  String get healthMinutes => pick('min', 'דק׳');
  String get healthActiveKcal => pick('Active calories', 'קלוריות פעילות');
  String get healthBaseGoal => pick('Base goal', 'יעד בסיס');
  String get healthLastSync => pick('Last sync', 'סנכרון אחרון');
  String get healthNever => pick('Never', 'אף פעם');
  String get healthConnected => pick('Connected', 'מחובר');
  String get healthNotConnected => pick('Not connected', 'לא מחובר');
  String get healthStepGoal => pick('Daily step goal', 'יעד צעדים יומי');
  String get healthExerciseGoal =>
      pick('Daily exercise goal (minutes)', 'יעד פעילות יומי (דקות)');
  String get healthActivityNote => pick(
    'While Apple Health is connected, the activity level is not used for your calorie goal.',
    'כש-Apple Health מחובר, רמת הפעילות אינה משמשת לחישוב יעד הקלוריות.',
  );
  String get healthConnect =>
      pick('Connect Apple Health', 'חיבור Apple Health');
  String get healthDisconnect => pick('Disconnect', 'ניתוק');
  String get healthSyncNow => pick('Sync now', 'סנכרון עכשיו');
  String get healthDenied => pick(
    'Apple Health access was not granted.',
    'לא ניתנה גישה ל-Apple Health.',
  );
  String get healthSyncFailed => pick(
    'Apple Health could not be synced. Try again.',
    'לא ניתן לסנכרן את Apple Health. נסו שוב.',
  );
  String get healthSource => 'Apple Health';
  String get manualSource => pick('Manual', 'ידני');
  String get barcode => pick('Barcode', 'ברקוד');
  String get enterBarcode =>
      pick('Enter barcode manually', 'הזנת ברקוד ידנית');
  String get scan => pick('Scan', 'סריקה');
  String get lookUp => pick('Look up', 'חיפוש');
  String get searchFoods =>
      pick('Search foods or enter a barcode', 'חיפוש מזון או הזנת ברקוד');
  String get searchInstead => pick('Search or type a barcode', 'חיפוש או הקלדת ברקוד');
  String get recentFoods => pick('Recent', 'אחרונים');
  String get noMatches => pick('No matching foods.', 'לא נמצא מזון תואם.');
  String get measuredAs => pick('Measured as', 'נמדד לפי');
  String get optional => pick('Optional', 'רשות');
  String get cancel => pick('Cancel', 'ביטול');
  String get undo => pick('Undo', 'ביטול פעולה');
  String get kg => pick('kg', 'ק״ג');
  String get account => pick('Account', 'חשבון');
  String get off => pick('Off', 'כבוי');
  String get tagline =>
      pick('Calories and fasting, simply.', 'קלוריות וצום, בפשטות.');
  String stepOf(int n) => pick('Step $n of 2', 'שלב $n מתוך 2');
  String get goalAutoHint => pick(
    'Filled in once the fields above are set',
    'יתמלא אחרי שתמלאו את השדות למעלה',
  );
  String get fastingQuestionHint => pick(
    'You can change this any time in Settings.',
    'אפשר לשנות את זה בכל עת בהגדרות.',
  );

  /// Sunday-first short weekday names.
  List<String> get weekdaysShort => he
      ? const ['א׳', 'ב׳', 'ג׳', 'ד׳', 'ה׳', 'ו׳', 'ש׳']
      : const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  List<String> get monthsShort => he
      ? const ['ינו׳', 'פבר׳', 'מרץ', 'אפר׳', 'מאי', 'יוני', 'יולי', 'אוג׳', 'ספט׳', 'אוק׳', 'נוב׳', 'דצמ׳']
      : const ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// "Sun, 8 Nov" for a YYYY-MM-DD day.
  String dayLabel(String day) {
    final date = DateTime.parse('${day}T12:00:00Z');
    return '${weekdaysShort[date.weekday % 7]}, ${date.day} ${monthsShort[date.month - 1]}';
  }

  /// "2 – 8 Nov" (or "30 Nov – 6 Dec") for a Sunday-based week.
  String weekRange(String sunday) {
    final start = DateTime.parse('${sunday}T12:00:00Z');
    final end = start.add(const Duration(days: 6));
    if (start.month == end.month) {
      return '${start.day}–${end.day} ${monthsShort[end.month - 1]}';
    }
    return '${start.day} ${monthsShort[start.month - 1]} – ${end.day} ${monthsShort[end.month - 1]}';
  }
  String removedEntry(String name) => pick('Removed $name', '$name הוסר');
  String get log => pick('Log', 'רישום');
  String get menu => pick('Menu', 'תפריט');
  String get amount => pick('Amount', 'כמות');
  String get add => pick('Add', 'הוספה');
  String get createFood => pick('New food', 'מזון חדש');
  String get name => pick('Name', 'שם');
  String get solid => pick('Solid, per 100 g', 'מוצק, ל־100 גרם');
  String get liquid => pick('Liquid, per 100 ml', 'נוזל, ל־100 מ״ל');
  String get calories => pick('Calories (kcal)', 'קלוריות');
  String get protein => pick('Protein (g)', 'חלבון (גרם)');
  String get carbohydrates => pick('Carbohydrates (g)', 'פחמימות (גרם)');
  String get fat => pick('Fat (g)', 'שומן (גרם)');
  String get fiber => pick('Fiber (g)', 'סיבים (גרם)');
  String get sugars => pick('Sugars (g)', 'סוכרים (גרם)');
  String get sodium => pick('Sodium (mg)', 'נתרן (מ״ג)');
  String get publish => pick('Publish', 'פרסום');
  String get unpublish => pick('Stop sharing', 'הפסקת שיתוף');
  String get verify => pick('Verify', 'אימות');
  String get verified => pick('Verified', 'מאומת');
  String get chooseFood => pick('Choose a published food', 'בחירת מזון שפורסם');
  String get noFood => pick(
    'This barcode is not in the database yet.',
    'הברקוד הזה עדיין לא במאגר.',
  );
  String get emptyDay =>
      pick('No foods logged today.', 'עדיין לא נרשם מזון היום.');
  String get emptyMeal => pick('Nothing logged yet.', 'עדיין לא נרשם.');
  String get breakfast => pick('Breakfast', 'ארוחת בוקר');
  String get lunch => pick('Lunch', 'ארוחת צהריים');
  String get dinner => pick('Dinner', 'ארוחת ערב');
  String get snacks => pick('Snacks', 'חטיפים');
  String get kcal => pick('kcal', 'קק״ל');

  String mealLabel(String meal) {
    switch (meal) {
      case 'breakfast':
        return breakfast;
      case 'lunch':
        return lunch;
      case 'dinner':
        return dinner;
      default:
        return snacks;
    }
  }

  String get delete => pick('Remove', 'הסרה');
  String get success => pick('Goal met', 'היעד הושג');
  String get onTrack => pick('On track', 'בדרך ליעד');

  /// Label for the API's day status; "met" only once the day is over.
  String dayStatus(String? status) => switch (status) {
    'met' => success,
    'over' => missed,
    'on_track' => onTrack,
    _ => estimate,
  };
  String get missed => pick('Over goal', 'מעל היעד');
  String get notYet => pick('Not counted yet', 'עדיין לא נספר');
  String get calorieIntake => pick('Calorie intake', 'צריכת קלוריות');
  String get successCount => pick('Days on goal', 'ימים ביעד');
  String get weightChange => pick('Weight change', 'שינוי במשקל');
  String get noWeightChange => pick(
    'No weight change for this week yet.',
    'אין עדיין שינוי משקל לשבוע הזה.',
  );
  String get logWeight => pick('Log weight', 'רישום משקל');
  String get graphEmpty =>
      pick('Log a weight to see the graph.', 'רשמו משקל כדי לראות את הגרף.');
  String get autoPublish =>
      pick('Publish new foods by default', 'פרסום מזונות חדשים כברירת מחדל');
  String get fasting => pick('Intermittent fasting', 'צום לסירוגין');
  String get fastingTab => pick('Fasting', 'צום');
  String get moreDetails => pick('More details', 'פרטים נוספים');
  String get scheduled => pick('Scheduled', 'מתוזמן');
  String get startFast => pick('Start fast', 'התחל צום');
  String get stopFast => pick('Stop fast', 'עצור צום');
  String get timeLeft => pick('Time left', 'זמן שנותר');
  String get approximateEnd => pick('Approximate end', 'סיום משוער');
  String get fastLog => pick('Fasts', 'צומות');
  String get date => pick('Date', 'תאריך');
  String get length => pick('Length', 'משך');
  String get start => pick('Start', 'התחלה');
  String get end => pick('End', 'סיום');
  String get noFasts => pick('No fasts yet.', 'עדיין אין צומות.');
  String get approx => pick('approx.', 'משוער');
  String get language => pick('Language', 'שפה');
  String get english => 'English';
  String get hebrew => 'עברית';
  String get edit => pick('Edit', 'עריכה');
  String get grams => pick('grams', 'גרם');
  String get milliliters => pick('milliliters', 'מיליליטר');
  String get fastReminder => pick('Fast reminder', 'תזכורת צום');
  String get reminderAtStart => pick('At start hour', 'בשעת ההתחלה');
  String get reminder30Before => pick('30 minutes before', '30 דקות לפני');
  String get reminder1HourBefore => pick('1 hour before', 'שעה לפני');
  String get reminderLateNote => pick(
    'If you have not started yet, we will also nudge you 15 minutes after the start hour.',
    'אם עדיין לא התחלתם, נשלח גם תזכורת 15 דקות אחרי שעת ההתחלה.',
  );
  String get reminderStart =>
      pick('Time to start your fast', 'הגיע הזמן להתחיל את הצום');
  String get reminderLead30 => pick(
    'Your fast starts in 30 minutes',
    'הצום מתחיל בעוד 30 דקות',
  );
  String get reminderLead60 =>
      pick('Your fast starts in 1 hour', 'הצום מתחיל בעוד שעה');
  String get reminderLate => pick(
    "It's not too late to start fasting",
    'עדיין לא מאוחר להתחיל לצום',
  );
  String get reminderDone =>
      pick('Your fast timer is complete', 'טיימר הצום הסתיים');
  String get previousWeek => pick('Previous week', 'השבוע הקודם');
  String get nextWeek => pick('Next week', 'השבוע הבא');
  String get sedentary => pick('Sedentary', 'יושבני');
  String get light => pick('Lightly active', 'פעיל קלות');
  String get moderate => pick('Moderately active', 'פעיל במידה');
  String get very => pick('Very active', 'פעיל מאוד');
  String get extra => pick('Extra active', 'פעיל במיוחד');
  String get pace025 => pick('0.25 kg per week', '0.25 ק״ג בשבוע');
  String get pace050 => pick('0.5 kg per week', '0.5 ק״ג בשבוע');
  String get pace100 => pick('0.75 kg per week', '0.75 ק״ג בשבוע');

  String error(String code) => switch (code) {
    'email_taken' => pick(
      'That email is already registered.',
      'האימייל הזה כבר רשום.',
    ),
    'invalid_login' => pick(
      'Email or password is wrong.',
      'האימייל או הסיסמה שגויים.',
    ),
    'invalid_body' => pick(
      'Check the form and try again.',
      'בדקו את הטופס ונסו שוב.',
    ),
    'weak_password' => pick(
      'Password must be at least 8 English characters with an uppercase letter, a number, and a symbol.',
      'הסיסמה חייבת להכיל לפחות 8 תווים באנגלית, אות גדולה, ספרה ותו מיוחד.',
    ),
    'password_mismatch' => pick(
      'Passwords do not match.',
      'הסיסמאות אינן תואמות.',
    ),
    'wrong_password' => pick(
      'Current password is incorrect.',
      'הסיסמה הנוכחית שגויה.',
    ),
    'no_password' => pick(
      'This account signs in with Apple and has no password.',
      'החשבון הזה מתחבר עם Apple ואין לו סיסמה.',
    ),
    'apple_failed' => pick(
      'Apple sign-in failed. Try again.',
      'ההתחברות עם Apple נכשלה. נסו שוב.',
    ),
    'apple_unverified_email' => pick(
      'An account with this email exists, but Apple has not verified it. Log in with your password.',
      'קיים חשבון עם האימייל הזה, אבל Apple לא אימתה אותו. התחברו עם הסיסמה.',
    ),
    'apple_no_email' => pick(
      'Apple did not share an email address. Use email and password to sign up.',
      'Apple לא שיתפה כתובת אימייל. הירשמו עם אימייל וסיסמה.',
    ),
    'apple_unavailable' => pick(
      'Apple sign-in is not available right now.',
      'ההתחברות עם Apple אינה זמינה כרגע.',
    ),
    'forbidden' => pick(
      "You don't have permission for this action.",
      'אין לך הרשאה לבצע פעולה זו.',
    ),
    'already_exists' => pick(
      'You already have a food for this barcode.',
      'כבר יש לכם מזון לברקוד הזה.',
    ),
    'fasting_disabled' => pick(
      'Turn fasting on before starting the timer.',
      'הפעילו צום לפני התחלת הטיימר.',
    ),
    'timer_running' => pick('A timer is already running.', 'טיימר כבר רץ.'),
    _ => pick('Something went wrong.', 'משהו השתבש.'),
  };

  String operationLabel(String op) => switch (op) {
    'profile:read' => pick('Read profile & settings', 'צפייה בפרופיל והגדרות'),
    'profile:update' => pick('Update body profile', 'עדכון נתוני גוף'),
    'settings:update' => pick('Update user settings', 'עדכון הגדרות משתמש'),
    'days:read' => pick('View daily diary & goals', 'צפייה ביומן יומי ויעדים'),
    'entries:create' => pick('Log food entries', 'רישום אכילה ביומן'),
    'entries:delete' => pick('Remove food entries', 'מחיקת רישומי אכילה'),
    'foods:read' => pick('Search & view foods', 'חיפוש וצפייה במזונות'),
    'foods:create' => pick('Create new foods', 'יצירת מזונות חדשים'),
    'foods:update' => pick('Edit foods', 'עריכת מזונות'),
    'foods:publish' => pick(
      'Publish & unpublish foods',
      'פרסום והפסקת שיתוף מזונות',
    ),
    'foods:verify' => pick('Verify published foods', 'אימות מזונות שפורסמו'),
    'weeks:read' => pick('View weekly summary', 'צפייה בסיכום שבועי'),
    'weights:read' => pick('View weight history', 'צפייה בהיסטוריית משקל'),
    'weights:create' => pick('Log weight entries', 'רישום שקילות'),
    'fasting:read' => pick('View fasting status & log', 'צפייה במצב ויומן צום'),
    'fasting:update' => pick('Configure fasting settings', 'שינוי הגדרות צום'),
    'fasting:timer' => pick(
      'Start & stop fasting timer',
      'הפעלה ועצירה של טיימר צום',
    ),
    'appleHealth:read' => pick(
      'View Apple Health data',
      'צפייה בנתוני Apple Health',
    ),
    'appleHealth:sync' => pick('Sync Apple Health', 'סנכרון Apple Health'),
    _ => op,
  };

  String activityLabel(String key) => switch (key) {
    'light' => light,
    'moderate' => moderate,
    'very' => very,
    'extra' => extra,
    _ => sedentary,
  };

  String paceLabel(String key) => switch (key) {
    'kg025' => pace025,
    'kg100' => pace100,
    _ => pace050,
  };
}
