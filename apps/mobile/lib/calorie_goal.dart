int ageFromDob(DateTime dateOfBirth, [DateTime? onDay]) {
  final now = onDay ?? DateTime.now();
  var age = now.year - dateOfBirth.year;
  final beforeBirthday = now.month < dateOfBirth.month ||
      (now.month == dateOfBirth.month && now.day < dateOfBirth.day);
  if (beforeBirthday) age -= 1;
  return age < 0 ? 0 : age;
}

double mifflinStJeor({
  required String sex,
  required num weightKg,
  required num heightCm,
  required int age,
}) {
  final base = 10 * weightKg + 6.25 * heightCm - 5 * age;
  return sex == 'male' ? base + 5 : base - 161;
}

int sexCalorieFloor(String sex) => sex == 'male' ? 1500 : 1200;

int calorieSafetyFloor({
  required String sex,
  required num weightKg,
  required num heightCm,
  required int age,
}) {
  final bmr = mifflinStJeor(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
  ).round();
  final floor = sexCalorieFloor(sex);
  return bmr > floor ? bmr : floor;
}

const activityMultiplier = <String, double>{
  'sedentary': 1.2,
  'light': 1.375,
  'moderate': 1.55,
  'very': 1.725,
  'extra': 1.9,
};

const paceDeficit = <String, int>{
  'kg025': 275,
  'kg050': 550,
  'kg100': 750,
};

int suggestedCalorieGoal({
  required String sex,
  required num weightKg,
  required num heightCm,
  required int age,
  required String activity,
  required String pace,
}) {
  final resting = mifflinStJeor(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
  );
  final multiplier = activityMultiplier[activity] ?? 1.2;
  final deficit = paceDeficit[pace] ?? 550;
  final raw = resting * multiplier - deficit;
  final floor = calorieSafetyFloor(
    sex: sex,
    weightKg: weightKg,
    heightCm: heightCm,
    age: age,
  );
  return (raw > floor ? raw : floor).round();
}
