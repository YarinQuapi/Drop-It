class Copy {
  const Copy(this.lang);
  final String lang;
  bool get he => lang == 'he';

  String pick(String en, String he) => this.he ? he : en;

  String get appName => 'Drop It';
  String get login => pick('Log in', 'התחברות');
  String get signup => pick('Sign up', 'הרשמה');
  String get email => pick('Email', 'אימייל');
  String get password => pick('Password', 'סיסמה');
  String get today => pick('Today', 'היום');
  String get week => pick('Week', 'השבוע');
  String get weight => pick('Weight', 'משקל');
  String get settings => pick('Settings', 'הגדרות');
  String get logout => pick('Log out', 'יציאה');
  String get fastingQuestion => pick('Do you want to use intermittent fasting?', 'האם להשתמש בצום לסירוגין?');
  String get yes => pick('Yes', 'כן');
  String get no => pick('No', 'לא');
  String get continueLabel => pick('Continue', 'המשך');
  String get fastingLength => pick('Fasting length', 'משך הצום');
  String get startHour => pick('Hour to start the fast', 'שעה להתחלת הצום');
  String get endHour => pick('Approximate hour to end the fast', 'שעה משוערת לסיום הצום');
  String get hours => pick('hours', 'שעות');
  String get profileTitle => pick('Your body stats', 'נתוני הגוף');
  String get sex => pick('Sex', 'מין');
  String get male => pick('Male', 'זכר');
  String get female => pick('Female', 'נקבה');
  String get dateOfBirth => pick('Date of birth', 'תאריך לידה');
  String get height => pick('Height (cm)', 'גובה (ס״מ)');
  String get weightKg => pick('Weight (kg)', 'משקל (ק״ג)');
  String get activity => pick('Activity', 'פעילות');
  String get pace => pick('Weekly pace', 'קצב שבועי');
  String get save => pick('Save', 'שמירה');
  String get goal => pick('Calorie goal', 'יעד קלוריות');
  String get eaten => pick('Eaten', 'נאכל');
  String get remaining => pick('Remaining', 'נותר');
  String get estimate => pick('This number is an estimate from the Mifflin–St Jeor formula.', 'המספר הזה הוא אומדן לפי נוסחת מיפלין–סנט ג׳ור.');
  String get barcode => pick('Barcode', 'ברקוד');
  String get scan => pick('Scan', 'סריקה');
  String get lookUp => pick('Look up', 'חיפוש');
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
  String get noFood => pick('This barcode is not in the database yet.', 'הברקוד הזה עדיין לא במאגר.');
  String get emptyDay => pick('No foods logged today.', 'עדיין לא נרשם מזון היום.');
  String get delete => pick('Remove', 'הסרה');
  String get success => pick('Goal met', 'היעד הושג');
  String get missed => pick('Over goal', 'מעל היעד');
  String get notYet => pick('Not counted yet', 'עדיין לא נספר');
  String get calorieIntake => pick('Calorie intake', 'צריכת קלוריות');
  String get successCount => pick('Days on goal', 'ימים ביעד');
  String get weightChange => pick('Weight change', 'שינוי במשקל');
  String get noWeightChange => pick('No weight change for this week yet.', 'אין עדיין שינוי משקל לשבוע הזה.');
  String get logWeight => pick('Log weight', 'רישום משקל');
  String get graphEmpty => pick('Log a weight to see the graph.', 'רשמו משקל כדי לראות את הגרף.');
  String get autoPublish => pick('Publish new foods by default', 'פרסום מזונות חדשים כברירת מחדל');
  String get fasting => pick('Intermittent fasting', 'צום לסירוגין');
  String get startFast => pick('Start timer', 'התחלת טיימר');
  String get stopFast => pick('Stop timer', 'עצירת טיימר');
  String get timeLeft => pick('Time left', 'זמן שנותר');
  String get language => pick('Language', 'שפה');
  String get english => 'English';
  String get hebrew => 'עברית';
  String get edit => pick('Edit', 'עריכה');
  String get grams => pick('grams', 'גרם');
  String get milliliters => pick('milliliters', 'מיליליטר');
  String get reminderStart => pick('Time to start your fast', 'הגיע הזמן להתחיל את הצום');
  String get reminderEnd => pick('Your fast is near its end', 'הצום מתקרב לסיום');
  String get reminderDone => pick('Your fast timer is complete', 'טיימר הצום הסתיים');
  String get previousWeek => pick('Previous week', 'השבוע הקודם');
  String get nextWeek => pick('Next week', 'השבוע הבא');
  String get sedentary => pick('Sedentary', 'יושבני');
  String get light => pick('Lightly active', 'פעיל קלות');
  String get moderate => pick('Moderately active', 'פעיל במידה');
  String get very => pick('Very active', 'פעיל מאוד');
  String get extra => pick('Extra active', 'פעיל במיוחד');
  String get pace025 => pick('0.25 kg per week', '0.25 ק״ג בשבוע');
  String get pace050 => pick('0.5 kg per week', '0.5 ק״ג בשבוע');
  String get pace100 => pick('1 kg per week', '1 ק״ג בשבוע');

  String error(String code) => switch (code) {
        'email_taken' => pick('That email is already registered.', 'האימייל הזה כבר רשום.'),
        'invalid_login' => pick('Email or password is wrong.', 'האימייל או הסיסמה שגויים.'),
        'invalid_body' => pick('Check the form and try again.', 'בדקו את הטופס ונסו שוב.'),
        'already_exists' => pick('You already have a food for this barcode.', 'כבר יש לכם מזון לברקוד הזה.'),
        'fasting_disabled' => pick('Turn fasting on before starting the timer.', 'הפעילו צום לפני התחלת הטיימר.'),
        'timer_running' => pick('A timer is already running.', 'טיימר כבר רץ.'),
        _ => pick('Something went wrong.', 'משהו השתבש.'),
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
