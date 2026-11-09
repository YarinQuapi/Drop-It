import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';
import 'calorie_goal.dart';
import 'copy.dart';
import 'health.dart';
import 'reminders.dart';
import 'theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DropItApp());
}

class DropItApp extends StatefulWidget {
  const DropItApp({super.key});

  @override
  State<DropItApp> createState() => _DropItAppState();
}

class _DropItAppState extends State<DropItApp> with WidgetsBindingObserver {
  final Api api = Api();
  late final AppleHealth health = AppleHealth(api);
  final Reminders reminders = Reminders();
  Map<String, dynamic>? me;
  bool loading = true;
  String lang = 'en';
  String themeMode = 'system';

  Copy get t => Copy(lang);

  Future<void> setThemeMode(String mode) async {
    setState(() => themeMode = mode);
    await api.saveThemeMode(mode);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(boot());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        me != null &&
        me!['hasProfile'] == true) {
      unawaited(health.syncIfConnected());
      unawaited(syncReminders());
    }
  }

  Future<void> boot() async {
    themeMode = await api.loadThemeMode();
    // Signed-out default: the device language (the account's wins after login).
    lang =
        await api.loadLanguage() ??
        (WidgetsBinding.instance.platformDispatcher.locale.languageCode == 'he'
            ? 'he'
            : 'en');
    try {
      await reminders.init();
    } catch (_) {}
    await api.loadToken();
    if (api.token != null) {
      final cachedMe = await api.loadCachedMe();
      if (cachedMe != null) {
        me = cachedMe;
        lang = (cachedMe['user']?['language'] as String?) ?? 'en';
      }
      try {
        me = await api.send('GET', '/api/auth/me');
        lang = me!['user']['language'] as String;
        await api.saveCachedMe(me);
      } on ApiException catch (err) {
        if (err.statusCode == 401 || err.code == 'unauthorized') {
          await api.setToken(null);
          me = null;
        }
      } catch (_) {
        // Keep cached session and token if network/API is temporarily unreachable
      }
    }
    if (mounted) setState(() => loading = false);
    if (me != null && me!['hasProfile'] == true)
      unawaited(health.syncIfConnected());
    await syncReminders();
  }

  Future<void> syncReminders() async {
    if (api.token == null) return;
    try {
      final fasting = await api.send('GET', '/api/fasting');
      final notifications =
          ((fasting['notifications'] as List?) ?? const [])
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList();
      await reminders.schedule(
        notifications: notifications,
        copy: ReminderCopy(
          start: t.reminderStart,
          lead30: t.reminderLead30,
          lead60: t.reminderLead60,
          late: t.reminderLate,
          done: t.reminderDone,
        ),
      );
    } catch (_) {}
  }

  Future<void> afterAuth(Map<String, dynamic> auth) async {
    await api.setToken(auth['token'] as String);
    me = await api.send('GET', '/api/auth/me');
    lang = me!['user']['language'] as String;
    await api.saveCachedMe(me);
    setState(() {});
    if (me!['hasProfile'] == true) unawaited(health.syncIfConnected());
  }

  @override
  Widget build(BuildContext context) {
    final copy = t;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: copy.appName,
      themeMode: switch (themeMode) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      },
      theme: buildAppleTheme(Brightness.light),
      darkTheme: buildAppleTheme(Brightness.dark),
      home: Directionality(
        textDirection: lang == 'he' ? TextDirection.rtl : TextDirection.ltr,
        child: SoftSwitcher(
          child: loading
              ? const Scaffold(
                  key: ValueKey('loading'),
                  body: Center(child: CircularProgressIndicator()),
                )
              : me == null
              ? AuthScreen(
                  key: const ValueKey('auth'),
                  api: api,
                  t: copy,
                  onAuth: afterAuth,
                  onLang: (next) {
                    setState(() => lang = next);
                    unawaited(api.saveLanguage(next));
                  },
                )
              : me!['hasProfile'] != true
              ? SetupScreen(
                  key: const ValueKey('setup'),
                  api: api,
                  t: copy,
                  onReady: (next) {
                    unawaited(api.saveCachedMe(next));
                    setState(() => me = next);
                  },
                  sync: syncReminders,
                )
              : HomeScreen(
                  key: const ValueKey('home'),
                  api: api,
                  t: copy,
                  me: me!,
                  themeMode: themeMode,
                  onThemeMode: setThemeMode,
                  onMe: (next) {
                    unawaited(api.saveCachedMe(next));
                    setState(() {
                      me = next;
                      lang = next['user']['language'] as String;
                    });
                  },
                  onLogout: () async {
                    try {
                      await api.send('POST', '/api/auth/logout');
                    } catch (_) {}
                    await AppleHealth.stopLocal();
                    await api.setToken(null);
                    setState(() => me = null);
                  },
                  health: health,
                  sync: syncReminders,
                ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({
    super.key,
    required this.api,
    required this.t,
    required this.onAuth,
    required this.onLang,
  });
  final Api api;
  final Copy t;
  final Future<void> Function(Map<String, dynamic>) onAuth;
  final ValueChanged<String> onLang;

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final confirmPassword = TextEditingController();
  bool signup = false;
  bool appleBusy = false;
  String error = '';

  Future<void> _continueWithApple() async {
    final t = widget.t;
    final language = t.lang;
    setState(() {
      error = '';
      appleBusy = true;
    });
    try {
      final random = Random.secure();
      final rawNonce = List.generate(
        16,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ).join();
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256.convert(utf8.encode(rawNonce)).toString(),
      );
      final identityToken = credential.identityToken;
      if (identityToken == null) throw ApiException('apple_failed');
      final auth = await widget.api.send(
        'POST',
        '/api/auth/apple',
        body: {
          'identityToken': identityToken,
          'nonce': rawNonce,
          'language': language,
        },
      );
      await widget.onAuth(auth);
    } on SignInWithAppleAuthorizationException catch (err) {
      if (mounted && err.code != AuthorizationErrorCode.canceled)
        setState(() => error = t.error('apple_failed'));
    } on ApiException catch (err) {
      if (mounted) setState(() => error = t.error(err.code));
    } finally {
      if (mounted) setState(() => appleBusy = false);
    }
  }

  bool get _ruleLength =>
      password.text.length >= 8 && password.text.length <= 200;
  bool get _ruleEnglish =>
      password.text.isNotEmpty &&
      RegExp(r'^[\x21-\x7E]+$').hasMatch(password.text);
  bool get _ruleUppercase => RegExp(r'[A-Z]').hasMatch(password.text);
  bool get _ruleNumber => RegExp(r'[0-9]').hasMatch(password.text);
  bool get _ruleSymbol =>
      RegExp(r'[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]').hasMatch(password.text);
  bool get _ruleMatch =>
      password.text.isNotEmpty && password.text == confirmPassword.text;
  bool get _signupValid =>
      _ruleLength &&
      _ruleEnglish &&
      _ruleUppercase &&
      _ruleNumber &&
      _ruleSymbol &&
      _ruleMatch;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      body: SafeArea(
        child: AppList(
          gap: Gaps.md,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Gaps.xl, bottom: Gaps.sm),
              child: Column(
                spacing: 2,
                children: [
                  const AppMark(),
                  const SizedBox(height: Gaps.sm),
                  Text(
                    t.appName,
                    style: Theme.of(context).textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    t.tagline,
                    style: TextStyle(color: context.apple.labelSecondary),
                  ),
                ],
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                signup ? t.signup : t.login,
                key: ValueKey(signup),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            // Apple's own button keeps the required black/white pairing; the theme brightness picks which.
            SizedBox(
              height: Gaps.hit,
              child: IgnorePointer(
                ignoring: appleBusy,
                child: SignInWithAppleButton(
                  text: t.continueWithApple,
                  height: Gaps.hit,
                  borderRadius: BorderRadius.circular(Radii.control),
                  style: Theme.of(context).brightness == Brightness.dark
                      ? SignInWithAppleButtonStyle.white
                      : SignInWithAppleButtonStyle.black,
                  onPressed: _continueWithApple,
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Divider(
                    color: context.apple.separator,
                    thickness: 0.5,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
                  child: Text(
                    t.orDivider,
                    style: TextStyle(
                      color: context.apple.labelSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                Expanded(
                  child: Divider(
                    color: context.apple.separator,
                    thickness: 0.5,
                  ),
                ),
              ],
            ),
            TextField(
              controller: email,
              // Emails and passwords are Latin text: keep them LTR in Hebrew too.
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.email),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: password,
              // Emails and passwords are Latin text: keep them LTR in Hebrew too.
              textDirection: TextDirection.ltr,
              decoration: InputDecoration(labelText: t.password),
              obscureText: true,
              onChanged: (_) {
                if (signup) setState(() {});
              },
            ),
            if (signup) ...[
              TextField(
                controller: confirmPassword,
                // Emails and passwords are Latin text: keep them LTR in Hebrew too.
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: t.confirmPassword),
                obscureText: true,
                onChanged: (_) => setState(() {}),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Gaps.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.passwordRulesTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: Gaps.sm),
                      RuleRow(_ruleLength, t.ruleLength),
                      RuleRow(_ruleEnglish, t.ruleEnglish),
                      RuleRow(_ruleUppercase, t.ruleUppercase),
                      RuleRow(_ruleNumber, t.ruleNumber),
                      RuleRow(_ruleSymbol, t.ruleSymbol),
                      RuleRow(_ruleMatch, t.ruleMatch),
                    ],
                  ),
                ),
              ),
            ],
            if (error.isNotEmpty) ErrorText(error),
            FilledButton(
              onPressed: signup && !_signupValid
                  ? null
                  : () async {
                      try {
                        final body = signup
                            ? {
                                'email': email.text.trim(),
                                'password': password.text,
                                'confirmPassword': confirmPassword.text,
                                'language':
                                    Localizations.localeOf(context)
                                            .languageCode ==
                                        'he'
                                    ? 'he'
                                    : 'en',
                              }
                            : {
                                'email': email.text.trim(),
                                'password': password.text,
                              };
                        final auth = await widget.api.send(
                          'POST',
                          signup ? '/api/auth/signup' : '/api/auth/login',
                          body: body,
                        );
                        await widget.onAuth(auth);
                      } on ApiException catch (err) {
                        setState(() => error = t.error(err.code));
                      }
                    },
              child: Text(signup ? t.signup : t.login),
            ),
            TextButton(
              onPressed: () => setState(() {
                signup = !signup;
                error = '';
              }),
              child: Text(signup ? t.login : t.signup),
            ),
            Center(
              child: SizedBox(
                width: 240,
                child: AppleSegmented<String>(
                  value: t.lang,
                  options: const [
                    AppleMenuOption('en', 'English'),
                    AppleMenuOption('he', 'עברית'),
                  ],
                  onChanged: widget.onLang,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Chevron that points to the trailing (or, with [back], leading) side, so it
/// mirrors in RTL. CupertinoIcons chevrons do not flip on their own.
class DirectionalChevron extends StatelessWidget {
  const DirectionalChevron({super.key, this.back = false, this.color, this.size});
  final bool back;
  final Color? color;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final pointsLeft = back != rtl;
    return Icon(
      pointsLeft ? CupertinoIcons.chevron_left : CupertinoIcons.chevron_right,
      color: color,
      size: size,
    );
  }
}

/// App mark: a drop on the accent tile.
class AppMark extends StatelessWidget {
  const AppMark({super.key, this.size = 56});
  final double size;

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: apple.accentPrimary,
        borderRadius: BorderRadius.circular(size * 0.25),
      ),
      child: Icon(
        CupertinoIcons.drop_fill,
        color: Theme.of(context).colorScheme.onPrimary,
        size: size * 0.55,
      ),
    );
  }
}

class SetupScreen extends StatefulWidget {
  const SetupScreen({
    super.key,
    required this.api,
    required this.t,
    required this.onReady,
    required this.sync,
  });
  final Api api;
  final Copy t;
  final ValueChanged<Map<String, dynamic>> onReady;
  final Future<void> Function() sync;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  bool? wants;
  int length = 16;
  int startHour = 20;
  // No silent default: the user picks explicitly.
  String? sex;
  DateTime? birthDate;
  final height = TextEditingController();
  final weight = TextEditingController();
  final dailyGoal = TextEditingController();
  String activity = 'sedentary';
  String pace = 'kg050';
  bool touchedGoal = false;
  bool profileStep = false;
  String error = '';

  int? get _suggested {
    final heightCm = parseDecimal(height.text);
    final weightKg = parseDecimal(weight.text);
    if (sex == null ||
        birthDate == null ||
        heightCm == null ||
        weightKg == null) {
      return null;
    }
    return suggestedCalorieGoal(
      sex: sex!,
      weightKg: weightKg,
      heightCm: heightCm,
      age: ageFromDob(birthDate!),
      activity: activity,
      pace: pace,
    );
  }

  void _syncSuggestedGoal() {
    if (touchedGoal) return;
    final suggested = _suggested;
    if (suggested != null) dailyGoal.text = '$suggested';
  }

  @override
  void dispose() {
    height.dispose();
    weight.dispose();
    dailyGoal.dispose();
    super.dispose();
  }

  Widget _stepLabel(int step) => Text(
    widget.t.stepOf(step),
    style: TextStyle(
      color: context.apple.labelSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w600,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      body: SafeArea(
        child: SoftSwitcher(
          child: AppList(
            key: ValueKey(profileStep),
            gap: Gaps.md,
            children: [
              if (!profileStep) ...[
                _stepLabel(1),
                Text(
                  t.fastingQuestion,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  t.fastingQuestionHint,
                  style: TextStyle(color: context.apple.labelSecondary),
                ),
                AppleSegmented<bool>(
                  large: true,
                  value: wants,
                  options: [
                    AppleMenuOption(true, t.yes),
                    AppleMenuOption(false, t.no),
                  ],
                  onChanged: (value) => setState(() => wants = value),
                ),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 280),
                  sizeCurve: Curves.easeOutCubic,
                  crossFadeState: wants == true
                      ? CrossFadeState.showSecond
                      : CrossFadeState.showFirst,
                  firstChild: const SizedBox(width: double.infinity),
                  secondChild: Column(
                    children: [
                      // Room for the floating label: the cross-fade clips its child.
                      const SizedBox(height: Gaps.md),
                      AppleMenuField<int>(
                        label: t.fastingLength,
                        value: length,
                        options: [12, 14, 16]
                            .map(
                              (value) =>
                                  AppleMenuOption(value, '$value ${t.hours}'),
                            )
                            .toList(),
                        onChanged: (value) => setState(() => length = value),
                      ),
                      const SizedBox(height: Gaps.md),
                      hourPicker(
                        t.startHour,
                        startHour,
                        (value) => setState(() => startHour = value),
                      ),
                      const SizedBox(height: Gaps.md),
                      Text(
                        '${t.endHour}: ${((startHour + length) % 24).toString().padLeft(2, '0')}:00',
                      ),
                    ],
                  ),
                ),
                if (error.isNotEmpty) ErrorText(error),
                FilledButton(
                  onPressed: wants == null
                      ? null
                      : () async {
                          try {
                            await widget.api.send(
                              'PUT',
                              '/api/fasting',
                              body: {
                                'enabled': wants == true,
                                'lengthHours': length,
                                'startHour': startHour,
                              },
                            );
                            await widget.sync();
                            setState(() => profileStep = true);
                          } on ApiException catch (err) {
                            setState(() => error = t.error(err.code));
                          }
                        },
                  child: Text(t.continueLabel),
                ),
              ] else ...[
                _stepLabel(2),
                Text(
                  t.profileTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                AppleSegmented<String>(
                  label: t.sex,
                  value: sex,
                  options: [
                    AppleMenuOption('female', t.female),
                    AppleMenuOption('male', t.male),
                  ],
                  onChanged: (value) => setState(() {
                    sex = value;
                    _syncSuggestedGoal();
                  }),
                ),
                AppleDateField(
                  label: t.dateOfBirth,
                  value: birthDate,
                  doneLabel: t.done,
                  onChanged: (value) => setState(() {
                    birthDate = value;
                    _syncSuggestedGoal();
                  }),
                ),
                decimalField(
                  height,
                  t.height,
                  onChanged: (_) => setState(_syncSuggestedGoal),
                ),
                decimalField(
                  weight,
                  t.weightKg,
                  onChanged: (_) => setState(_syncSuggestedGoal),
                ),
                AppleMenuField<String>(
                  label: t.activity,
                  value: activity,
                  options: ['sedentary', 'light', 'moderate', 'very', 'extra']
                      .map(
                        (value) =>
                            AppleMenuOption(value, t.activityLabel(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    activity = value;
                    _syncSuggestedGoal();
                  }),
                ),
                AppleMenuField<String>(
                  label: t.pace,
                  value: pace,
                  options: ['kg025', 'kg050', 'kg100']
                      .map(
                        (value) => AppleMenuOption(value, t.paceLabel(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() {
                    pace = value;
                    _syncSuggestedGoal();
                  }),
                ),
                decimalField(
                  dailyGoal,
                  t.dailyGoal,
                  helper: dailyGoal.text.isEmpty ? t.goalAutoHint : null,
                  onChanged: (_) => setState(() => touchedGoal = true),
                ),
                // Only offered once the goal differs from the suggestion.
                if (_suggested != null && touchedGoal)
                  OutlinedButton(
                    onPressed: () => setState(() {
                      touchedGoal = false;
                      dailyGoal.text = '${_suggested!}';
                    }),
                    child: Text(
                      touchedGoal
                          ? '${t.useSuggested} (${_suggested!})'
                          : t.useSuggested,
                    ),
                  ),
                Text(
                  t.goalFloorNote,
                  style: TextStyle(color: context.apple.labelSecondary),
                ),
                if (error.isNotEmpty) ErrorText(error),
                FilledButton(
                  onPressed: birthDate == null || sex == null
                      ? null
                      : () async {
                          final heightCm = parseDecimal(height.text);
                          final weightKg = parseDecimal(weight.text);
                          final goalKcal = parseDecimal(dailyGoal.text)?.round();
                          if (heightCm == null ||
                              weightKg == null ||
                              goalKcal == null) {
                            setState(() => error = t.error('invalid_body'));
                            return;
                          }
                          try {
                            await widget.api.send(
                              'PUT',
                              '/api/profile',
                              body: {
                                'sex': sex,
                                'dateOfBirth': formatIsoDate(birthDate!),
                                'heightCm': heightCm,
                                'weightKg': weightKg,
                                'activity': activity,
                                'weeklyPace': pace,
                                'customGoalKcal': goalKcal,
                              },
                            );
                            widget.onReady(
                              await widget.api.send('GET', '/api/auth/me'),
                            );
                          } on ApiException catch (err) {
                            setState(() => error = t.error(err.code));
                          } catch (_) {
                            setState(() => error = t.error('invalid_body'));
                          }
                        },
                  child: Text(t.save),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.api,
    required this.t,
    required this.me,
    required this.themeMode,
    required this.onThemeMode,
    required this.onMe,
    required this.onLogout,
    required this.health,
    required this.sync,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final String themeMode;
  final ValueChanged<String> onThemeMode;
  final ValueChanged<Map<String, dynamic>> onMe;
  final Future<void> Function() onLogout;
  final AppleHealth health;
  final Future<void> Function() sync;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    final isAdmin = widget.me['user']['isAdmin'] == true;
    final perms = ((widget.me['permissions'] as List?) ?? []).cast<String>();
    final canVerifyFoods = isAdmin || perms.contains('foods:verify');
    // Top-level destinations live in a tab bar (HIG); log out and admin tools
    // are inside Settings.
    final tabs = <(String, IconData, IconData, Widget)>[
      (
        t.today,
        CupertinoIcons.sun_max,
        CupertinoIcons.sun_max_fill,
        TodayScreen(
          api: widget.api,
          t: t,
          admin: canVerifyFoods,
          sync: widget.sync,
        ),
      ),
      (
        t.week,
        CupertinoIcons.chart_bar,
        CupertinoIcons.chart_bar_fill,
        WeekScreen(api: widget.api, t: t),
      ),
      (
        t.fastingTab,
        CupertinoIcons.timer,
        CupertinoIcons.timer_fill,
        FastingScreen(api: widget.api, t: t, sync: widget.sync),
      ),
      (
        t.weight,
        CupertinoIcons.gauge,
        CupertinoIcons.gauge,
        WeightScreen(api: widget.api, t: t),
      ),
      (
        t.settings,
        CupertinoIcons.gear,
        CupertinoIcons.gear_solid,
        SettingsScreen(
          api: widget.api,
          t: t,
          me: widget.me,
          themeMode: widget.themeMode,
          onThemeMode: widget.onThemeMode,
          onMe: widget.onMe,
          health: widget.health,
          sync: widget.sync,
          onLogout: widget.onLogout,
          isAdmin: isAdmin,
        ),
      ),
    ];
    final safeIndex = index < tabs.length ? index : 0;
    return Scaffold(
      appBar: AppBar(title: Text(tabs[safeIndex].$1)),
      body: SoftSwitcher(
        child: KeyedSubtree(
          key: ValueKey(safeIndex),
          child: tabs[safeIndex].$4,
        ),
      ),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: safeIndex,
        onTap: (value) => setState(() => index = value),
        activeColor: apple.accentPrimary,
        inactiveColor: apple.labelSecondary,
        backgroundColor: apple.glass,
        border: Border(
          top: BorderSide(color: apple.separator, width: 0.5),
        ),
        items: [
          for (final tab in tabs)
            BottomNavigationBarItem(
              icon: Icon(tab.$2),
              activeIcon: Icon(tab.$3),
              label: tab.$1,
            ),
        ],
      ),
    );
  }
}

class TodayScreen extends StatefulWidget {
  const TodayScreen({
    super.key,
    required this.api,
    required this.t,
    required this.admin,
    required this.sync,
  });
  final Api api;
  final Copy t;
  final bool admin;
  final Future<void> Function() sync;

  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

const _meals = ['breakfast', 'lunch', 'dinner', 'snacks'];

class _TodayScreenState extends State<TodayScreen> {
  late Map<String, dynamic>? day = widget.api.peek('/api/days/today');
  late Map<String, dynamic>? fasting = widget.api.peek('/api/fasting');
  String error = '';
  Timer? ticker;

  /// Entries removed but still inside their Undo window (hidden locally).
  final Set<String> hiddenEntries = {};

  void _removeEntry(Map entry) {
    final id = entry['id'] as String;
    final t = widget.t;
    setState(() => hiddenEntries.add(id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: Text(
              t.removedEntry(entry['name'] as String),
              overflow: TextOverflow.ellipsis,
            ),
            duration: const Duration(seconds: 6),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.control),
            ),
            action: SnackBarAction(
              label: t.undo,
              onPressed: () {
                if (mounted) setState(() => hiddenEntries.remove(id));
              },
            ),
          ),
        )
        .closed
        .then((reason) async {
          if (reason == SnackBarClosedReason.action) return;
          try {
            await widget.api.send('DELETE', '/api/days/today/entries/$id');
          } on ApiException catch (err) {
            if (mounted) setState(() => error = t.error(err.code));
          }
          hiddenEntries.remove(id);
          if (mounted) await load();
        });
  }

  @override
  void initState() {
    super.initState();
    AppleHealth.synced.addListener(_onHealthSynced);
    _ensureTicker();
    unawaited(load());
  }

  @override
  void dispose() {
    ticker?.cancel();
    AppleHealth.synced.removeListener(_onHealthSynced);
    super.dispose();
  }

  void _onHealthSynced() {
    if (mounted) unawaited(load());
  }

  Future<void> load() async {
    Map<String, dynamic>? nextDay = day;
    Map<String, dynamic>? nextFast = fasting;
    var nextError = '';
    try {
      nextDay = await widget.api.send('GET', '/api/days/today');
    } on ApiException catch (err) {
      nextError = widget.t.error(err.code);
    }
    try {
      nextFast = await widget.api.send('GET', '/api/fasting');
    } on ApiException catch (err) {
      if (nextError.isEmpty) nextError = widget.t.error(err.code);
    }
    if (!mounted) return;
    setState(() {
      day = nextDay;
      fasting = nextFast;
      error = nextError;
    });
    _ensureTicker();
  }

  void _ensureTicker() {
    final running = fasting?['running'] == true;
    if (running) {
      ticker ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      ticker?.cancel();
      ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final totals = (day?['totals'] as Map?)?.cast<String, dynamic>();
    final allEntries = ((day?['entries'] as List?) ?? []).cast<Map>();
    final entries = allEntries
        .where((entry) => !hiddenEntries.contains(entry['id']))
        .toList();
    final hiddenKcal = allEntries
        .where((entry) => hiddenEntries.contains(entry['id']))
        .fold<num>(0, (sum, entry) => sum + ((entry['calories'] as num?) ?? 0));
    final goal = (day?['goalKcal'] as num?) ?? 0;
    final eaten = ((totals?['calories'] as num?) ?? 0) - hiddenKcal;
    final remaining = goal - eaten;
    final over = eaten > goal;
    final apple = context.apple;
    final mealKcal = <String, num>{
      for (final meal in _meals)
        meal: entries
            .where((entry) => (entry['meal'] as String? ?? 'snacks') == meal)
            .fold<num>(0, (sum, entry) => sum + ((entry['calories'] as num?) ?? 0)),
    };
    final eatenBasis = over && eaten > 0 ? eaten : goal;
    final ringSlices = [
      for (final meal in _meals)
        _RingSlice(
          _mealColor(apple, meal),
          eatenBasis <= 0 ? 0 : (mealKcal[meal]! / eatenBasis).toDouble(),
        ),
    ];
    return AppList(
      children: [
        if (day != null)
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Radii.sheet),
              side: Theme.of(context).brightness == Brightness.dark
                  ? BorderSide(color: apple.separator, width: 0.5)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 132,
                        height: 132,
                        child: Stack(
                          alignment: Alignment.center,
                          clipBehavior: Clip.none,
                          children: [
                            Transform.translate(
                              offset: const Offset(0, -10),
                              child: SizedBox(
                                width: 132,
                                height: 132,
                                child: EaseBuilder(
                                  from: 0,
                                  value: 1,
                                  builder: (context, progress) => CustomPaint(
                                    painter: _MealRingPainter(
                                      slices: ringSlices,
                                      track: apple.tertiaryFill,
                                      progress: progress,
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                EaseBuilder(
                                  from: goal.toDouble(),
                                  value: remaining.toDouble(),
                                  builder: (context, value) => Text(
                                    _grouped(value),
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineMedium
                                        ?.copyWith(
                                          color: over
                                              ? apple.accentDangerText
                                              : null,
                                        ),
                                  ),
                                ),
                                Text(
                                  t.remaining,
                                  style: TextStyle(
                                    color: apple.labelSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${t.goal}  ${_grouped(goal)} ${t.kcal}'),
                            Text('${t.eaten}  ${_grouped(eaten)} ${t.kcal}'),
                            const SizedBox(height: Gaps.xs),
                            Text(
                              t.dayStatus(day!['status'] as String?),
                              style: TextStyle(
                                color: apple.labelSecondary,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (day!['healthSynced'] == true) ...[
                    const SizedBox(height: Gaps.lg),
                    HealthProgressRow(
                      label: t.healthSteps,
                      value: (day!['steps'] as num?) ?? 0,
                      goal: (day!['stepGoal'] as num?) ?? 0,
                    ),
                    const SizedBox(height: Gaps.md),
                    HealthProgressRow(
                      label: t.healthExercise,
                      value: (day!['exerciseMinutes'] as num?) ?? 0,
                      goal: (day!['exerciseGoalMinutes'] as num?) ?? 0,
                      unit: t.healthMinutes,
                    ),
                  ],
                  if (mealKcal.values.any((calories) => calories > 0)) ...[
                    const SizedBox(height: Gaps.md),
                    Wrap(
                      spacing: Gaps.md,
                      runSpacing: Gaps.sm,
                      children: [
                        for (final meal in _meals)
                          if ((mealKcal[meal] ?? 0) > 0)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _mealColor(apple, meal),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  t.mealLabel(meal),
                                  style: TextStyle(
                                    color: apple.labelSecondary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (fasting != null)
          _TodayFastCard(
            t: t,
            fasting: fasting!,
            onToggle: () async {
              try {
                await widget.api.send(
                  'POST',
                  fasting!['running'] == true
                      ? '/api/fasting/stop'
                      : '/api/fasting/start',
                );
                await load();
                await widget.sync();
              } on ApiException catch (err) {
                if (mounted) setState(() => error = t.error(err.code));
              }
            },
            onDetails: () async {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => FastingScreen(
                    api: widget.api,
                    t: t,
                    sync: widget.sync,
                  ),
                ),
              );
              if (mounted) await load();
            },
          ),
        if (error.isNotEmpty) ErrorText(error),
        for (final meal in _meals) ...[
          _MealCard(
            t: t,
            meal: meal,
            entries: entries
                .where(
                  (entry) => (entry['meal'] as String? ?? 'snacks') == meal,
                )
                .toList(),
            onLog: () => _logMeal(meal),
            onDelete: _removeEntry,
          ),
        ],
      ],
    );
  }

  Future<void> _logMeal(String meal) async {
    final t = widget.t;
    final result = await Navigator.push<ScanOutcome>(
      context,
      MaterialPageRoute(builder: (_) => ScanScreen(manualLabel: t.searchInstead)),
    );
    if (!mounted || result == null) return;
    if (result.manual) {
      final found = await Navigator.push<FoodSearchOutcome>(
        context,
        MaterialPageRoute(
          builder: (_) => FoodSearchScreen(api: widget.api, t: t),
        ),
      );
      if (!mounted || found == null) return;
      if (found.food != null) {
        await addFood(found.food!, meal, initialAmount: found.lastAmount);
      } else if (found.barcode != null) {
        await lookup(found.barcode!, meal);
      } else {
        final created = await Navigator.push<Map<String, dynamic>>(
          context,
          MaterialPageRoute(
            builder: (_) =>
                FoodScreen(api: widget.api, t: t, initialName: found.newName),
          ),
        );
        if (created != null && mounted) await addFood(created, meal);
      }
      return;
    }
    final code = result.code;
    if (code != null && code.isNotEmpty) await lookup(code, meal);
  }

  Future<void> lookup(String barcode, String meal) async {
    final t = widget.t;
    final Map<String, dynamic> result;
    try {
      result = await widget.api.send(
        'GET',
        '/api/foods/barcode/${Uri.encodeComponent(barcode)}',
      );
    } on ApiException catch (err) {
      if (mounted) setState(() => error = t.error(err.code));
      return;
    }
    if (!mounted) return;
    Map<String, dynamic>? food = (result['food'] as Map?)
        ?.cast<String, dynamic>();
    if (result['status'] == 'none') {
      food = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(
          builder: (_) => FoodScreen(api: widget.api, t: t, barcode: barcode),
        ),
      );
    } else if (result['status'] == 'list') {
      final foods = (result['foods'] as List).cast<Map>();
      food = await showModalBottomSheet<Map<String, dynamic>>(
        context: context,
        builder: (context) => ListView(
          children: [
            ListTile(title: Text(t.chooseFood)),
            for (final item in foods)
              ListTile(
                title: Text(item['name'] as String),
                subtitle: Text(item['verified'] == true ? t.verified : ''),
                onTap: () =>
                    Navigator.pop(context, item.cast<String, dynamic>()),
              ),
          ],
        ),
      );
    }
    if (food == null || !mounted) return;
    await addFood(food, meal);
  }

  /// One sheet: the food, an amount with a live calorie total, and Add.
  Future<void> addFood(
    Map<String, dynamic> food,
    String meal, {
    num? initialAmount,
  }) async {
    final t = widget.t;
    final picked = await showModalBottomSheet<FoodPick>(
      context: context,
      isScrollControlled: true,
      builder: (context) => FoodActions(
        api: widget.api,
        t: t,
        food: food,
        admin: widget.admin,
        initialAmount: initialAmount ?? 100,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.api.send(
        'POST',
        '/api/days/today/entries',
        body: {
          'foodId': picked.food['id'],
          'amount': picked.amount,
          'meal': meal,
        },
      );
      await load();
      await widget.sync();
    } on ApiException catch (err) {
      setState(() => error = t.error(err.code));
    }
  }
}

class _MealCard extends StatelessWidget {
  const _MealCard({
    required this.t,
    required this.meal,
    required this.entries,
    required this.onLog,
    required this.onDelete,
  });

  final Copy t;
  final String meal;
  final List<Map> entries;
  final VoidCallback onLog;
  final void Function(Map entry) onDelete;

  @override
  Widget build(BuildContext context) {
    final mealKcal = entries.fold<num>(
      0,
      (sum, entry) => sum + ((entry['calories'] as num?) ?? 0),
    );
    final apple = context.apple;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    t.mealLabel(meal),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  '${_grouped(mealKcal)} ${t.kcal}',
                  style: TextStyle(
                    fontWeight: mealKcal > 0 ? FontWeight.w600 : FontWeight.w500,
                    // Zero is not a warning: secondary until something is logged.
                    color: mealKcal > 0
                        ? apple.accentEnergyText
                        : apple.labelSecondary,
                  ),
                ),
              ],
            ),
            if (entries.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: Gaps.xs, bottom: Gaps.sm),
                child: Text(
                  t.emptyMeal,
                  style: TextStyle(color: apple.labelSecondary, fontSize: 14),
                ),
              ),
            for (final entry in entries) ...[
              Divider(color: apple.separator, thickness: 0.5, height: Gaps.md),
              FadeIn(
                key: ValueKey(entry['id']),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  minTileHeight: Gaps.hit,
                  title: Text(entry['name'] as String),
                  subtitle: Text(
                    '${entry['amount']} ${entry['basis'] == 'solid' ? t.grams : t.milliliters}',
                    style: TextStyle(color: apple.labelSecondary),
                  ),
                  trailing: SizedBox(
                    width: 116,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          _grouped((entry['calories'] as num?) ?? 0),
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: apple.accentDangerText,
                          ),
                          onPressed: () => onDelete(entry),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Gaps.md),
            FilledButton(onPressed: onLog, child: Text(t.log)),
          ],
        ),
      ),
    );
  }
}

class ScanOutcome {
  const ScanOutcome.scanned(this.code) : manual = false;
  const ScanOutcome.manual() : code = null, manual = true;

  final String? code;
  final bool manual;
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key, required this.manualLabel});

  final String manualLabel;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool done = false;

  void finish(ScanOutcome outcome) {
    if (done) return;
    done = true;
    Navigator.pop(context, outcome);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            onDetect: (capture) {
              final value = capture.barcodes.isEmpty
                  ? null
                  : capture.barcodes.first.rawValue;
              if (value == null || value.isEmpty) return;
              finish(ScanOutcome.scanned(value));
            },
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: Gaps.hit,
                  child: FilledButton(
                    onPressed: () => finish(const ScanOutcome.manual()),
                    child: Text(widget.manualLabel),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What the search screen hands back: a food to log, a barcode to look up,
/// or a request to create a new food (prefilled with [newName]).
class FoodSearchOutcome {
  const FoodSearchOutcome.food(Map<String, dynamic> this.food, {this.lastAmount})
    : barcode = null,
      newName = null;
  const FoodSearchOutcome.barcode(String this.barcode)
    : food = null,
      lastAmount = null,
      newName = null;
  const FoodSearchOutcome.create(this.newName)
    : food = null,
      lastAmount = null,
      barcode = null;

  final Map<String, dynamic>? food;
  final num? lastAmount;
  final String? barcode;
  final String? newName;
}

class FoodSearchScreen extends StatefulWidget {
  const FoodSearchScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<FoodSearchScreen> createState() => _FoodSearchScreenState();
}

class _FoodSearchScreenState extends State<FoodSearchScreen> {
  final query = TextEditingController();
  Timer? debounce;
  List<Map<String, dynamic>> recent = [];
  List<Map<String, dynamic>>? results;
  String error = '';
  int searchId = 0;

  static final _barcodePattern = RegExp(r'^\d{6,}$');

  @override
  void initState() {
    super.initState();
    widget.api
        .send('GET', '/api/foods/recent')
        .then((data) {
          if (!mounted) return;
          setState(
            () => recent = (data['foods'] as List)
                .map((item) => (item as Map).cast<String, dynamic>())
                .toList(),
          );
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    debounce?.cancel();
    query.dispose();
    super.dispose();
  }

  void onChanged(String value) {
    debounce?.cancel();
    final text = value.trim();
    if (text.length < 2) {
      setState(() => results = null);
      return;
    }
    debounce = Timer(const Duration(milliseconds: 250), () => search(text));
    setState(() {});
  }

  Future<void> search(String text) async {
    final id = ++searchId;
    try {
      final data = await widget.api.send(
        'GET',
        '/api/foods/search?q=${Uri.encodeQueryComponent(text)}',
      );
      if (!mounted || id != searchId) return;
      setState(() {
        error = '';
        results = (data['foods'] as List)
            .map((item) => (item as Map).cast<String, dynamic>())
            .toList();
      });
    } on ApiException catch (err) {
      if (mounted) setState(() => error = widget.t.error(err.code));
    }
  }

  void submit() {
    final text = query.text.trim();
    if (_barcodePattern.hasMatch(text)) {
      Navigator.pop(context, FoodSearchOutcome.barcode(text));
    } else if (results?.length == 1) {
      Navigator.pop(context, FoodSearchOutcome.food(results!.first));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    final text = query.text.trim();
    final isBarcode = _barcodePattern.hasMatch(text);
    final showRecent = text.length < 2 && recent.isNotEmpty;
    final list = showRecent ? recent : (results ?? const []);

    Widget row(Map<String, dynamic> food) {
      final unit = food['basis'] == 'solid' ? t.grams : t.milliliters;
      final last = food['lastAmount'] as num?;
      final detail = [
        last != null
            ? '${_plainNumber(last)} $unit'
            : '${_plainNumber((food['calories'] as num?) ?? 0)} ${t.kcal} / 100 $unit',
        if (food['verified'] == true) t.verified,
      ].join(' · ');
      return ListTile(
        minTileHeight: Gaps.hit,
        contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
        title: Text(food['name'] as String, overflow: TextOverflow.ellipsis),
        subtitle: Text(detail, style: TextStyle(color: apple.labelSecondary)),
        trailing: Icon(Icons.add_circle, color: apple.accentPrimary),
        onTap: () => Navigator.pop(
          context,
          FoodSearchOutcome.food(food, lastAmount: last),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(t.log)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, Gaps.md),
            child: TextField(
              controller: query,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t.searchFoods,
                prefixIcon: const Icon(Icons.search),
              ),
              onChanged: onChanged,
              onSubmitted: (_) => submit(),
            ),
          ),
          if (isBarcode)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
              child: FilledButton(onPressed: submit, child: Text(t.lookUp)),
            ),
          if (error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: ErrorText(error),
            ),
          if (showRecent)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, Gaps.xs),
              child: Text(
                t.recentFoods,
                style: TextStyle(
                  color: apple.labelSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          for (final food in list) row(food),
          if (!showRecent && results != null && results!.isEmpty && !isBarcode)
            Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: Gaps.sm,
                children: [
                  Text(t.noMatches, style: TextStyle(color: apple.labelSecondary)),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(context, FoodSearchOutcome.create(text)),
                    child: Text(t.createFood),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TodayFastCard extends StatelessWidget {
  const _TodayFastCard({
    required this.t,
    required this.fasting,
    required this.onToggle,
    required this.onDetails,
  });

  final Copy t;
  final Map<String, dynamic> fasting;
  final VoidCallback onToggle;
  final VoidCallback onDetails;

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    final running = fasting['running'] == true;
    final enabled = fasting['enabled'] == true;
    final endsAt = fasting['endsAt'] as String?;
    final left = !running || endsAt == null
        ? Duration.zero
        : DateTime.parse(endsAt).difference(DateTime.now());
    final hours =
        ((fasting['lengthHoursRunning'] ?? fasting['lengthHours']) as num?) ??
        0;
    final totalMs = hours * 3600000;
    final remainingMs = left.isNegative ? 0 : left.inMilliseconds;
    final ratio = !running || totalMs <= 0
        ? 0.0
        : ((totalMs - remainingMs) / totalMs).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: CircularProgressIndicator(
                    value: ratio,
                    strokeWidth: 8,
                    // A round cap at 0% would draw a stray dot.
                    strokeCap: ratio > 0 ? StrokeCap.round : StrokeCap.butt,
                    backgroundColor: apple.tertiaryFill,
                    color: apple.accentEnergy,
                  ),
                ),
                const SizedBox(width: Gaps.lg),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        t.fasting,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: Gaps.xs),
                      if (enabled && running) ...[
                        Text(
                          _clock(left),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.4,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          '${t.approximateEnd}: ${endsAt == null ? '' : _jerusalemTime(endsAt)}',
                          style: TextStyle(
                            color: apple.labelSecondary,
                            fontSize: 13,
                          ),
                        ),
                      ] else if (enabled)
                        Text(
                          '${t.scheduled}: ${fasting['startHour'].toString().padLeft(2, '0')}:00 – ${fasting['endHour'].toString().padLeft(2, '0')}:00 · ${fasting['lengthHours']} ${t.hours}',
                          style: TextStyle(color: apple.labelSecondary),
                        )
                      else
                        Text(
                          t.error('fasting_disabled'),
                          style: TextStyle(color: apple.labelSecondary),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: Gaps.md),
            Row(
              children: [
                if (enabled) ...[
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: running
                            ? apple.tertiaryFill
                            : apple.accentEnergy.withValues(alpha: 0.16),
                        foregroundColor: running
                            ? apple.accentDangerText
                            : apple.accentEnergyText,
                        elevation: 0,
                        shadowColor: Colors.transparent,
                      ),
                      onPressed: onToggle,
                      child: Text(running ? t.stopFast : t.startFast),
                    ),
                  ),
                  const SizedBox(width: Gaps.sm),
                ],
                Expanded(
                  child: TextButton(
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(Gaps.hit),
                    ),
                    onPressed: onDetails,
                    child: Text(t.moreDetails),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingSlice {
  const _RingSlice(this.color, this.fraction);

  final Color color;
  final double fraction;
}

Color _mealColor(AppleColors apple, String meal) {
  switch (meal) {
    case 'breakfast':
      return apple.accentPrimary;
    case 'lunch':
      return apple.accentEnergy;
    case 'dinner':
      return apple.accentSuccess;
    default:
      return apple.labelSecondary;
  }
}

class _MealRingPainter extends CustomPainter {
  _MealRingPainter({
    required this.slices,
    required this.track,
    required this.progress,
  });

  final List<_RingSlice> slices;
  final Color track;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 10.0;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );
    final active = slices.where((slice) => slice.fraction > 0).toList();
    final gap = active.length > 1 ? 0.08 : 0.0;
    final rect = Rect.fromCircle(center: center, radius: radius);
    var start = -pi / 2 + gap / 2;
    for (final slice in active) {
      final sweep = slice.fraction * progress * 2 * pi;
      final separated = sweep > gap * 2;
      final drawn = separated ? sweep - gap : sweep;
      if (drawn > 0) {
        canvas.drawArc(
          rect,
          start,
          drawn,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = stroke
            ..strokeCap = StrokeCap.round
            ..color = slice.color,
        );
      }
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_MealRingPainter old) {
    if (old.progress != progress ||
        old.track != track ||
        old.slices.length != slices.length) {
      return true;
    }
    for (var i = 0; i < slices.length; i++) {
      if (old.slices[i].color != slices[i].color ||
          old.slices[i].fraction != slices[i].fraction) {
        return true;
      }
    }
    return false;
  }
}

class FastingScreen extends StatefulWidget {
  const FastingScreen({
    super.key,
    required this.api,
    required this.t,
    required this.sync,
  });
  final Api api;
  final Copy t;
  final Future<void> Function() sync;

  @override
  State<FastingScreen> createState() => _FastingScreenState();
}

class _FastingScreenState extends State<FastingScreen> {
  late Map<String, dynamic>? fasting = widget.api.peek('/api/fasting');
  String error = '';
  Timer? ticker;

  @override
  void initState() {
    super.initState();
    unawaited(load());
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final next = await widget.api.send('GET', '/api/fasting');
      setState(() {
        fasting = next;
        error = '';
      });
    } on ApiException catch (err) {
      setState(() => error = widget.t.error(err.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final running = fasting?['running'] == true;
    final enabled = fasting?['enabled'] == true;
    final endsAt = fasting?['endsAt'] as String?;
    final left = endsAt == null
        ? Duration.zero
        : DateTime.parse(endsAt).difference(DateTime.now());
    final totalHours =
        (fasting?['lengthHoursRunning'] ?? fasting?['lengthHours']) as num? ?? 0;
    final totalMs = totalHours * 3600 * 1000;
    final leftMs = left.isNegative ? 0 : left.inMilliseconds;
    final fastRatio = totalMs > 0
        ? ((totalMs - leftMs) / totalMs).clamp(0.0, 1.0).toDouble()
        : 0.0;
    final sessions = ((fasting?['sessions'] as List?) ?? []).cast<Map>();
    final apple = context.apple;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AppList(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: running ? null : apple.cardBg,
            gradient: running
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: apple.fastGradient,
                  )
                : null,
            borderRadius: BorderRadius.circular(Radii.sheet),
            border: !running && dark
                ? Border.all(color: apple.separator, width: 0.5)
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  t.fasting,
                  style: TextStyle(
                    color: running ? Colors.white : null,
                    fontWeight: FontWeight.w700,
                    fontSize: 28,
                    letterSpacing: -0.6,
                  ),
                ),
                if (enabled && running) ...[
                  const SizedBox(height: Gaps.md),
                  Center(
                    child: SizedBox(
                      width: 230,
                      height: 230,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: CircularProgressIndicator(
                              value: fastRatio,
                              strokeWidth: 12,
                              strokeCap: fastRatio > 0
                                  ? StrokeCap.round
                                  : StrokeCap.butt,
                              backgroundColor: Colors.white24,
                              color: Colors.white,
                            ),
                          ),
                          Text(
                            _clock(left),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w300,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: Gaps.md),
                  Text(
                    '${t.approximateEnd}: ${endsAt == null ? '' : _jerusalemTime(endsAt)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
                if (enabled && !running)
                  Text(
                    '${t.scheduled}: ${fasting!['startHour'].toString().padLeft(2, '0')}:00 – ${fasting!['endHour'].toString().padLeft(2, '0')}:00 · ${fasting!['lengthHours']} ${t.hours}',
                    style: TextStyle(color: apple.labelSecondary),
                  ),
                const SizedBox(height: Gaps.md),
                if (enabled)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: running ? Colors.white : null,
                      foregroundColor: running ? apple.fastButtonText : null,
                      textStyle: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onPressed: () async {
                      try {
                        await widget.api.send(
                          'POST',
                          running ? '/api/fasting/stop' : '/api/fasting/start',
                        );
                        await load();
                        await widget.sync();
                      } on ApiException catch (err) {
                        setState(() => error = t.error(err.code));
                      }
                    },
                    child: Text(running ? t.stopFast : t.startFast),
                  )
                else if (fasting != null)
                  Text(t.error('fasting_disabled')),
                if (error.isNotEmpty)
                  running
                      ? Text(error, style: const TextStyle(color: Colors.white))
                      : ErrorText(error),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.fastLog,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 19,
                  ),
                ),
                const SizedBox(height: Gaps.sm),
                if (sessions.isEmpty)
                  Text(t.noFasts, style: TextStyle(color: apple.labelSecondary))
                else
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.4),
                      1: FlexColumnWidth(1.1),
                      2: FlexColumnWidth(0.9),
                      3: FlexColumnWidth(1.3),
                    },
                    children: [
                      TableRow(
                        children: [
                          _cell(t.date, header: true),
                          _cell(t.length, header: true),
                          _cell(t.start, header: true),
                          _cell(t.end, header: true),
                        ],
                      ),
                      for (final session in sessions)
                        TableRow(
                          children: [
                            _cell(
                              _jerusalemDate(session['startedAt'] as String),
                            ),
                            _cell(_fastLength(session)),
                            _cell(
                              _jerusalemTime(session['startedAt'] as String),
                            ),
                            _cell(_fastEnd(session, t.approx)),
                          ],
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

Widget _cell(String text, {bool header = false}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Text(
      text,
      style: TextStyle(
        fontWeight: header ? FontWeight.w700 : null,
        fontSize: header ? 13 : 14,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}

class WeekScreen extends StatefulWidget {
  const WeekScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<WeekScreen> createState() => _WeekScreenState();
}

class _WeekScreenState extends State<WeekScreen> {
  late Map<String, dynamic>? week = widget.api.peek('/api/weeks');
  String? on;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final path = '/api/weeks${on == null ? '' : '?on=$on'}';
    final cached = widget.api.peek(path);
    if (cached != null && week != cached) setState(() => week = cached);
    final data = await widget.api.send('GET', path);
    if (!mounted || path != '/api/weeks${on == null ? '' : '?on=$on'}') return;
    setState(() => week = data);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (week == null) return const Center(child: CircularProgressIndicator());
    final sunday = week!['sunday'] as String;
    final today = _todayJerusalem();
    final isCurrentWeek = _shift(sunday, 7).compareTo(today) > 0;
    final allDays = (week!['days'] as List).cast<Map>();
    final days = allDays
        .where(
          (day) =>
              day['future'] != true && ((day['calories'] as num?) ?? 0) > 0,
        )
        .toList();
    final byDay = {for (final day in allDays) day['day'] as String: day};
    final dailyGoal = ((week!['goalKcal'] as num?) ?? 0) / 7;
    final chart = [
      for (var i = 0; i < 7; i++)
        (
          date: _shift(sunday, i),
          calories: ((byDay[_shift(sunday, i)]?['calories'] as num?) ?? 0)
              .toDouble(),
          status: byDay[_shift(sunday, i)]?['status'] as String?,
        ),
    ];
    final scale = [
      dailyGoal * 1.25,
      ...chart.map((day) => day.calories),
      1.0,
    ].reduce(max);
    final apple = context.apple;
    final weekNavStyle = IconButton.styleFrom(
      backgroundColor: apple.accentTint,
      foregroundColor: apple.accentPrimary,
      disabledBackgroundColor: apple.tertiaryFill,
      disabledForegroundColor: apple.labelSecondary,
    );
    final change = week!['weightChangeKg'] as num?;
    Color barColor(String? status) => switch (status) {
      'met' => apple.accentSuccess,
      'over' => apple.accentEnergy,
      _ => apple.accentPrimary,
    };
    Widget stat(String label, String value, [String? suffix]) => Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: Gaps.md,
          vertical: Gaps.sm,
        ),
        decoration: BoxDecoration(
          color: apple.tertiaryFill,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(color: apple.labelSecondary, fontSize: 12),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (suffix != null)
              Text(
                suffix,
                style: TextStyle(color: apple.labelSecondary, fontSize: 12),
              ),
          ],
        ),
      ),
    );
    return FadeIn(
      key: ValueKey(sunday),
      child: AppList(
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          t.weekRange(sunday),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton.filled(
                        style: weekNavStyle,
                        tooltip: t.previousWeek,
                        onPressed: () {
                          on = _shift(sunday, -7);
                          load();
                        },
                        icon: const DirectionalChevron(back: true),
                      ),
                      const SizedBox(width: Gaps.sm),
                      IconButton.filled(
                        style: weekNavStyle,
                        tooltip: t.nextWeek,
                        onPressed: isCurrentWeek
                            ? null
                            : () {
                                on = _shift(sunday, 7);
                                load();
                              },
                        icon: const DirectionalChevron(),
                      ),
                    ],
                  ),
                  const SizedBox(height: Gaps.lg),
                  SizedBox(
                    height: 150,
                    child: Stack(
                      children: [
                        Positioned.fill(
                          bottom: 22,
                          child: Align(
                            alignment: Alignment(0, 1 - 2 * (dailyGoal / scale)),
                            child: Container(
                              height: 1,
                              color: apple.labelSecondary.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final day in chart)
                              Expanded(
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          width: 26,
                                          decoration: BoxDecoration(
                                            color: apple.tertiaryFill,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          alignment: Alignment.bottomCenter,
                                          child: FractionallySizedBox(
                                            heightFactor: (day.calories / scale)
                                                .clamp(0.0, 1.0),
                                            widthFactor: 1,
                                            child: Container(
                                              decoration: BoxDecoration(
                                                color: barColor(day.status),
                                                borderRadius:
                                                    BorderRadius.circular(8),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      t.weekdaysShort[DateTime.parse(
                                            '${day.date}T12:00:00Z',
                                          ).weekday %
                                          7],
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: day.date == today
                                            ? apple.accentPrimary
                                            : apple.labelSecondary,
                                        fontWeight: day.date == today
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: Gaps.lg),
                  Row(
                    spacing: Gaps.sm,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      stat(
                        t.calorieIntake,
                        _grouped((week!['calorieIntake'] as num?) ?? 0),
                        '/ ${_grouped((week!['goalKcal'] as num?) ?? 0)}',
                      ),
                      stat(t.successCount, '${week!['successCount']}'),
                      stat(
                        t.weightChange,
                        change == null
                            ? '—'
                            : '${change > 0 ? '+' : ''}$change ${t.kg}',
                      ),
                    ],
                  ),
                  if (change == null) ...[
                    const SizedBox(height: Gaps.sm),
                    Text(
                      t.noWeightChange,
                      style: TextStyle(color: apple.labelSecondary),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (days.isNotEmpty)
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < days.length; i++) ...[
                    if (i > 0)
                      Divider(
                        color: apple.separator,
                        thickness: 0.5,
                        height: 0.5,
                        indent: Gaps.lg,
                      ),
                    ListTile(
                      minTileHeight: Gaps.hit,
                      title: Text(t.dayLabel(days[i]['day'] as String)),
                      subtitle: Text(
                        [
                          '${_grouped(days[i]['calories'] as num)} / ${_grouped(days[i]['goalKcal'] as num)} ${t.kcal}',
                          if (days[i]['steps'] != null)
                            '${t.healthSteps} ${_grouped(days[i]['steps'] as num)} · ${t.healthExercise} ${days[i]['exerciseMinutes'] ?? 0} ${t.healthMinutes}',
                        ].join('\n'),
                        style: TextStyle(color: apple.labelSecondary),
                      ),
                      trailing: Text(
                        t.dayStatus(days[i]['status'] as String?),
                        style: TextStyle(
                          color: switch (days[i]['status']) {
                            'met' => apple.accentSuccessText,
                            'over' => apple.accentEnergyText,
                            _ => apple.labelSecondary,
                          },
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Today's date in Jerusalem as YYYY-MM-DD (the API's day boundary).
String _todayJerusalem() {
  final now = tz.TZDateTime.now(tz.getLocation('Asia/Jerusalem'));
  return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
}

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  late List<Map<String, dynamic>> weights =
      ((widget.api.peek('/api/weights')?['weights'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();
  final controller = TextEditingController();
  String error = '';

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final data = await widget.api.send('GET', '/api/weights');
    setState(
      () => weights = (data['weights'] as List).cast<Map<String, dynamic>>(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    return AppList(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                decimalField(controller, t.weightKg),
                if (error.isNotEmpty) ...[
                  const SizedBox(height: Gaps.sm),
                  ErrorText(error),
                ],
                const SizedBox(height: Gaps.md),
                FilledButton(
                  onPressed: () async {
                    final weightKg = parseDecimal(controller.text);
                    if (weightKg == null) {
                      setState(() => error = t.error('invalid_body'));
                      return;
                    }
                    try {
                      await widget.api.send(
                        'POST',
                        '/api/weights',
                        body: {'weightKg': weightKg},
                      );
                      controller.clear();
                      setState(() => error = '');
                      await load();
                    } on ApiException catch (err) {
                      setState(() => error = t.error(err.code));
                    }
                  },
                  child: Text(t.logWeight),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (weights.isEmpty)
                  Text(
                    t.graphEmpty,
                    style: TextStyle(color: apple.labelSecondary),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: AnimatedWeightChart(weights: weights),
                  ),
                for (final point in weights.reversed) ...[
                  Divider(
                    color: apple.separator,
                    thickness: 0.5,
                    height: Gaps.md,
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    minTileHeight: Gaps.hit,
                    title: Text('${point['weightKg']} kg'),
                    subtitle: Text(
                      '${_jerusalemDate(point['loggedAt'] as String)} ${_jerusalemTime(point['loggedAt'] as String)} · ${point['source'] == 'health' ? t.healthSource : t.manualSource}',
                      style: TextStyle(color: apple.labelSecondary),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class WeightPainter extends CustomPainter {
  WeightPainter(this.weights, this.progress, this.color, this.healthColor);
  final List<Map<String, dynamic>> weights;
  final double progress;
  final Color color;
  final Color healthColor;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = color.withValues(alpha: progress.clamp(0, 1));
    if (weights.length < 2) {
      if (weights.isNotEmpty) {
        canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, dot);
      }
      return;
    }
    final times = weights
        .map(
          (point) =>
              DateTime.parse(point['loggedAt'] as String).millisecondsSinceEpoch
                  .toDouble(),
        )
        .toList();
    final values = weights
        .map((point) => (point['weightKg'] as num).toDouble())
        .toList();
    final minT = times.reduce((a, b) => a < b ? a : b);
    final maxT = times.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    final spots = <Offset>[];
    for (var i = 0; i < weights.length; i++) {
      final x = maxT == minT
          ? size.width / 2
          : (times[i] - minT) / (maxT - minT) * (size.width - 16) + 8;
      final y = maxV == minV
          ? size.height / 2
          : size.height -
                8 -
                (values[i] - minV) / (maxV - minV) * (size.height - 16);
      final spot = Offset(x, y);
      spots.add(spot);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final metric = path.computeMetrics().first;
    canvas.drawPath(
      metric.extractPath(0, metric.length * progress.clamp(0, 1)),
      paint,
    );
    for (var i = 0; i < spots.length; i++) {
      final along = i / (spots.length - 1);
      if (along > progress) continue;
      canvas.drawCircle(
        spots[i],
        4,
        Paint()..color = weights[i]['source'] == 'health' ? healthColor : color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant WeightPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.weights != weights ||
      oldDelegate.color != color ||
      oldDelegate.healthColor != healthColor;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.api,
    required this.t,
    required this.me,
    required this.themeMode,
    required this.onThemeMode,
    required this.onMe,
    required this.health,
    required this.sync,
    required this.onLogout,
    this.isAdmin = false,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final String themeMode;
  final ValueChanged<String> onThemeMode;
  final ValueChanged<Map<String, dynamic>> onMe;
  final AppleHealth health;
  final Future<void> Function() sync;
  final Future<void> Function() onLogout;
  final bool isAdmin;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late Map<String, dynamic>? profile =
      (widget.api.peek('/api/profile')?['profile'] as Map?)
          ?.cast<String, dynamic>();
  late Map<String, dynamic>? fasting = widget.api.peek('/api/fasting');
  late Map<String, dynamic>? healthState = widget.api.peek('/api/apple-health');
  late final stepGoal = TextEditingController(
    text: healthState == null ? '' : '${healthState!['stepGoal']}',
  );
  late final exerciseGoal = TextEditingController(
    text: healthState == null ? '' : '${healthState!['exerciseGoalMinutes']}',
  );
  String healthError = '';
  bool healthBusy = false;
  bool autoPublish = false;

  List get _permissions => (widget.me['permissions'] as List?) ?? const [];
  bool get _canReadHealth => _permissions.contains('appleHealth:read');
  bool get _canSyncHealth => _permissions.contains('appleHealth:sync');

  Future<void> loadHealth() async {
    if (!_canReadHealth) return;
    try {
      final state = await widget.api.send('GET', '/api/apple-health');
      if (!mounted) return;
      setState(() {
        healthState = state;
        stepGoal.text = '${state['stepGoal']}';
        exerciseGoal.text = '${state['exerciseGoalMinutes']}';
      });
    } on ApiException catch (_) {}
  }

  Future<void> runHealth(Future<bool> Function() action) async {
    setState(() {
      healthBusy = true;
      healthError = '';
    });
    var ok = true;
    try {
      ok = await action();
    } on ApiException catch (err) {
      ok = false;
      if (mounted) healthError = widget.t.error(err.code);
    } on HealthSyncException catch (err) {
      ok = false;
      if (mounted) {
        healthError = err.denied
            ? widget.t.healthDenied
            : widget.t.healthSyncFailed;
      }
    }
    if (!mounted) return;
    setState(() {
      healthBusy = false;
      if (!ok && healthError.isEmpty) healthError = widget.t.healthDenied;
    });
    await loadHealth();
    await widget.sync();
  }

  Future<void> saveHealthGoals() async {
    final steps = int.tryParse(stepGoal.text.trim());
    final minutes = int.tryParse(exerciseGoal.text.trim());
    if (steps == null || minutes == null) {
      setState(() => healthError = widget.t.error('invalid_body'));
      return;
    }
    try {
      await widget.api.send(
        'PUT',
        '/api/apple-health/settings',
        body: {'stepGoal': steps, 'exerciseGoalMinutes': minutes},
      );
      if (mounted) setState(() => healthError = '');
      await loadHealth();
    } on ApiException catch (err) {
      if (mounted) setState(() => healthError = widget.t.error(err.code));
    }
  }

  Widget _healthCard(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    final state = healthState!;
    final connected = state['connected'] == true;
    final lastSync = state['lastSyncedAt'] as String?;
    final canConnect = AppleHealth.supported && _canSyncHealth;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.appleHealth,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Gaps.md),
            Text(connected ? t.healthConnected : t.healthNotConnected),
            const SizedBox(height: Gaps.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  t.healthLastSync,
                  style: TextStyle(color: apple.labelSecondary),
                ),
                Text(lastSync ?? t.healthNever),
              ],
            ),
            if (connected) ...[
              const SizedBox(height: Gaps.sm),
              Text(
                t.healthActivityNote,
                style: TextStyle(color: apple.labelSecondary, fontSize: 13),
              ),
            ],
            if (canConnect) ...[
              const SizedBox(height: Gaps.md),
              if (!connected)
                FilledButton(
                  onPressed: healthBusy
                      ? null
                      : () => runHealth(widget.health.connect),
                  child: Text(t.healthConnect),
                )
              else ...[
                FilledButton(
                  onPressed: healthBusy
                      ? null
                      : () => runHealth(widget.health.sync),
                  child: Text(t.healthSyncNow),
                ),
                const SizedBox(height: Gaps.sm),
                OutlinedButton(
                  onPressed: healthBusy
                      ? null
                      : () => runHealth(() async {
                          await widget.health.disconnect();
                          return true;
                        }),
                  child: Text(t.healthDisconnect),
                ),
              ],
            ],
            if (connected || lastSync != null) ...[
              const SizedBox(height: Gaps.md),
              TextField(
                controller: stepGoal,
                decoration: InputDecoration(labelText: t.healthStepGoal),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: Gaps.md),
              TextField(
                controller: exerciseGoal,
                decoration: InputDecoration(labelText: t.healthExerciseGoal),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: Gaps.md),
              FilledButton(
                onPressed: _canSyncHealth ? saveHealthGoals : null,
                child: Text(t.save),
              ),
            ],
            if (healthError.isNotEmpty) ...[
              const SizedBox(height: Gaps.sm),
              ErrorText(healthError),
            ],
          ],
        ),
      ),
    );
  }

  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  String passwordError = '';
  String passwordStatus = '';

  bool get _ruleLength =>
      newPassword.text.length >= 8 && newPassword.text.length <= 200;
  bool get _ruleEnglish =>
      newPassword.text.isNotEmpty &&
      RegExp(r'^[\x21-\x7E]+$').hasMatch(newPassword.text);
  bool get _ruleUppercase => RegExp(r'[A-Z]').hasMatch(newPassword.text);
  bool get _ruleNumber => RegExp(r'[0-9]').hasMatch(newPassword.text);
  bool get _ruleSymbol =>
      RegExp(r'[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]')
          .hasMatch(newPassword.text);
  bool get _ruleMatch =>
      newPassword.text.isNotEmpty && newPassword.text == confirmPassword.text;
  bool get _passwordValid =>
      currentPassword.text.isNotEmpty &&
      _ruleLength &&
      _ruleEnglish &&
      _ruleUppercase &&
      _ruleNumber &&
      _ruleSymbol &&
      _ruleMatch;

  @override
  void initState() {
    super.initState();
    autoPublish = widget.me['user']['autoPublishFoods'] == true;
    unawaited(load());
    unawaited(loadHealth());
  }

  @override
  void dispose() {
    stepGoal.dispose();
    exerciseGoal.dispose();
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    _revision.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final profileResponse = await widget.api.send('GET', '/api/profile');
    final fastingResponse = await widget.api.send('GET', '/api/fasting');
    setState(() {
      profile = (profileResponse['profile'] as Map?)?.cast<String, dynamic>();
      fasting = fastingResponse;
    });
  }

  /// Bumped on every setState so pushed section pages rebuild too.
  final _revision = ValueNotifier(0);

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _revision.value++;
  }

  void _openSection(String title, List<Widget> Function(BuildContext) build) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: ValueListenableBuilder<int>(
            valueListenable: _revision,
            builder: (context, _, _) => AppList(children: build(context)),
          ),
        ),
      ),
    );
  }

  Widget _row(
    String title, {
    String? value,
    Color? color,
    bool chevron = true,
    required VoidCallback onTap,
  }) {
    final apple = context.apple;
    return ListTile(
      minTileHeight: Gaps.hit,
      title: Text(title, style: TextStyle(color: color)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: Gaps.xs,
        children: [
          if (value != null)
            Text(value, style: TextStyle(color: apple.labelSecondary)),
          if (chevron)
            DirectionalChevron(color: apple.labelSecondary, size: 18),
        ],
      ),
      onTap: onTap,
    );
  }

  List<Widget> _profileSection(BuildContext context) {
    final t = widget.t;
    return [
        if (profile != null)
          ProfileEditor(
            key: ValueKey(
              [
                profile!['sex'],
                profile!['dateOfBirth'],
                profile!['heightCm'],
                profile!['weightKg'],
                profile!['activity'],
                profile!['weeklyPace'],
                profile!['customGoalKcal'],
              ].join('|'),
            ),
            api: widget.api,
            t: t,
            profile: profile!,
            onSaved: () async {
              await load();
              await widget.sync();
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
    ];
  }

  List<Widget> _fastingSection(BuildContext context) {
    final t = widget.t;
    return [
        if (fasting != null)
          FastingEditor(
            t: t,
            fasting: fasting!,
            onSave: (body) async {
              await widget.api.send('PUT', '/api/fasting', body: body);
              await load();
              await widget.sync();
              if (context.mounted) Navigator.of(context).maybePop();
            },
          ),
    ];
  }

  List<Widget> _healthSection(BuildContext context) => [
        if (healthState != null) _healthCard(context),
  ];

  List<Widget> _accountSection(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    return [
        if (widget.me['hasPassword'] != false)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    t.changePassword,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Gaps.md),
                  TextField(
                    controller: currentPassword,
                    // Emails and passwords are Latin text: keep them LTR in Hebrew too.
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: t.currentPassword),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gaps.md),
                  TextField(
                    controller: newPassword,
                    // Emails and passwords are Latin text: keep them LTR in Hebrew too.
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: t.newPassword),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gaps.md),
                  TextField(
                    controller: confirmPassword,
                    // Emails and passwords are Latin text: keep them LTR in Hebrew too.
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(labelText: t.confirmPassword),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gaps.md),
                  Text(
                    t.passwordRulesTitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: Gaps.xs),
                  RuleRow(_ruleLength, t.ruleLength),
                  RuleRow(_ruleEnglish, t.ruleEnglish),
                  RuleRow(_ruleUppercase, t.ruleUppercase),
                  RuleRow(_ruleNumber, t.ruleNumber),
                  RuleRow(_ruleSymbol, t.ruleSymbol),
                  RuleRow(_ruleMatch, t.ruleMatch),
                  if (passwordError.isNotEmpty) ...[
                    const SizedBox(height: Gaps.sm),
                    ErrorText(passwordError),
                  ],
                  if (passwordStatus.isNotEmpty) ...[
                    const SizedBox(height: Gaps.sm),
                    Text(
                      passwordStatus,
                      style: TextStyle(color: apple.accentSuccessText),
                    ),
                  ],
                  const SizedBox(height: Gaps.md),
                  FilledButton(
                    onPressed: !_passwordValid
                        ? null
                        : () async {
                            try {
                              await widget.api.send(
                                'PUT',
                                '/api/auth/password',
                                body: {
                                  'currentPassword': currentPassword.text,
                                  'newPassword': newPassword.text,
                                  'confirmPassword': confirmPassword.text,
                                },
                              );
                              if (mounted) {
                                setState(() {
                                  currentPassword.clear();
                                  newPassword.clear();
                                  confirmPassword.clear();
                                  passwordError = '';
                                  passwordStatus = t.passwordChanged;
                                });
                              }
                            } on ApiException catch (err) {
                              if (mounted) {
                                setState(() {
                                  passwordStatus = '';
                                  passwordError = t.error(err.code);
                                });
                              }
                            }
                          },
                    child: Text(t.save),
                  ),
                ],
              ),
            ),
          ),
        Card(
          child: Column(
            children: [
              if (widget.isAdmin)
                _row(
                  t.permissions,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Scaffold(
                        appBar: AppBar(title: Text(t.permissions)),
                        body: PermissionsScreen(api: widget.api, t: t),
                      ),
                    ),
                  ),
                ),
              _row(
                t.logout,
                color: apple.accentDangerText,
                chevron: false,
                onTap: () {
                  Navigator.of(context).maybePop();
                  widget.onLogout();
                },
              ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    final separator = Divider(
      color: apple.separator,
      thickness: 0.5,
      height: 0.5,
      indent: Gaps.lg,
    );
    return AppList(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AppleMenuField<String>(
                  label: t.language,
                  value: widget.me['user']['language'] as String,
                  options: [
                    AppleMenuOption('en', t.english),
                    AppleMenuOption('he', t.hebrew),
                  ],
                  onChanged: (value) async {
                    await widget.api.send(
                      'PUT',
                      '/api/profile/settings',
                      body: {
                        'language': value,
                        'autoPublishFoods': autoPublish,
                      },
                    );
                    widget.onMe(await widget.api.send('GET', '/api/auth/me'));
                  },
                ),
                const SizedBox(height: Gaps.lg),
                Text(
                  t.appearance,
                  style: TextStyle(
                    color: apple.labelSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: CupertinoSlidingSegmentedControl<String>(
                    groupValue: widget.themeMode,
                    backgroundColor: apple.tertiaryFill,
                    thumbColor: apple.cardBg,
                    children: {
                      'system': Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          t.themeSystem,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      'light': Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          t.themeLight,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                      'dark': Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          t.themeDark,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ),
                    },
                    onValueChanged: (value) {
                      if (value != null) widget.onThemeMode(value);
                    },
                  ),
                ),
                const SizedBox(height: Gaps.sm),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: Text(t.autoPublish),
                  value: autoPublish,
                  onChanged: (value) async {
                    setState(() => autoPublish = value);
                    await widget.api.send(
                      'PUT',
                      '/api/profile/settings',
                      body: {
                        'language': widget.me['user']['language'],
                        'autoPublishFoods': value,
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Column(
            children: [
              _row(
                t.profileTitle,
                onTap: () => _openSection(t.profileTitle, _profileSection),
              ),
              separator,
              _row(
                t.fasting,
                value: fasting == null
                    ? null
                    : fasting!['enabled'] == true
                    ? '${fasting!['lengthHours']} ${t.hours}'
                    : t.off,
                onTap: () => _openSection(t.fasting, _fastingSection),
              ),
              if (healthState != null) ...[
                separator,
                _row(
                  t.appleHealth,
                  value: healthState!['connected'] == true
                      ? t.healthConnected
                      : t.healthNotConnected,
                  onTap: () => _openSection(t.appleHealth, _healthSection),
                ),
              ],
              separator,
              _row(
                t.account,
                onTap: () => _openSection(t.account, _accountSection),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class ProfileEditor extends StatefulWidget {
  const ProfileEditor({
    super.key,
    required this.api,
    required this.t,
    required this.profile,
    required this.onSaved,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> profile;
  final Future<void> Function() onSaved;

  @override
  State<ProfileEditor> createState() => _ProfileEditorState();
}

class _ProfileEditorState extends State<ProfileEditor> {
  late String sex;
  late DateTime? birthDate;
  late final TextEditingController height;
  late final TextEditingController weight;
  late final TextEditingController dailyGoal;
  late String activity;
  late String pace;
  bool touchedGoal = false;
  String error = '';

  int? get _suggested {
    final heightCm = parseDecimal(height.text);
    final weightKg = parseDecimal(weight.text);
    if (birthDate == null || heightCm == null || weightKg == null) return null;
    return suggestedCalorieGoal(
      sex: sex,
      weightKg: weightKg,
      heightCm: heightCm,
      age: ageFromDob(birthDate!),
      activity: activity,
      pace: pace,
    );
  }

  void _syncSuggestedGoal() {
    if (touchedGoal) return;
    final suggested = _suggested;
    if (suggested != null) dailyGoal.text = '$suggested';
  }

  @override
  void initState() {
    super.initState();
    final p = widget.profile;
    sex = (p['sex'] as String?) ?? 'female';
    birthDate = DateTime.tryParse((p['dateOfBirth'] as String?) ?? '');
    height = TextEditingController(text: '${p['heightCm'] ?? ''}');
    weight = TextEditingController(text: '${p['weightKg'] ?? ''}');
    activity = (p['activity'] as String?) ?? 'sedentary';
    pace = (p['weeklyPace'] as String?) ?? 'kg050';
    final custom = p['customGoalKcal'];
    touchedGoal = custom != null;
    final seed = custom ?? _suggested;
    dailyGoal = TextEditingController(text: seed != null ? '$seed' : '');
  }

  @override
  void dispose() {
    height.dispose();
    weight.dispose();
    dailyGoal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.profileTitle,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: Gaps.md),
            AppleMenuField<String>(
              label: t.sex,
              value: sex,
              options: [
                AppleMenuOption('female', t.female),
                AppleMenuOption('male', t.male),
              ],
              onChanged: (value) => setState(() {
                sex = value;
                _syncSuggestedGoal();
              }),
            ),
            const SizedBox(height: Gaps.md),
            AppleDateField(
              label: t.dateOfBirth,
              value: birthDate,
              doneLabel: t.done,
              onChanged: (value) => setState(() {
                birthDate = value;
                _syncSuggestedGoal();
              }),
            ),
            const SizedBox(height: Gaps.md),
            decimalField(
              height,
              t.height,
              onChanged: (_) => setState(_syncSuggestedGoal),
            ),
            const SizedBox(height: Gaps.md),
            decimalField(
              weight,
              t.weightKg,
              onChanged: (_) => setState(_syncSuggestedGoal),
            ),
            const SizedBox(height: Gaps.md),
            AppleMenuField<String>(
              label: t.activity,
              value: activity,
              options: ['sedentary', 'light', 'moderate', 'very', 'extra']
                  .map(
                    (value) => AppleMenuOption(value, t.activityLabel(value)),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                activity = value;
                _syncSuggestedGoal();
              }),
            ),
            const SizedBox(height: Gaps.md),
            AppleMenuField<String>(
              label: t.pace,
              value: pace,
              options: ['kg025', 'kg050', 'kg100']
                  .map((value) => AppleMenuOption(value, t.paceLabel(value)))
                  .toList(),
              onChanged: (value) => setState(() {
                pace = value;
                _syncSuggestedGoal();
              }),
            ),
            const SizedBox(height: Gaps.md),
            decimalField(
              dailyGoal,
              t.dailyGoal,
              onChanged: (_) => setState(() => touchedGoal = true),
            ),
            if (_suggested != null && touchedGoal) ...[
              const SizedBox(height: Gaps.sm),
              OutlinedButton(
                onPressed: () => setState(() {
                  touchedGoal = false;
                  dailyGoal.text = '${_suggested!}';
                }),
                child: Text(
                  touchedGoal
                      ? '${t.useSuggested} (${_suggested!})'
                      : t.useSuggested,
                ),
              ),
            ],
            const SizedBox(height: Gaps.sm),
            Text(
              t.goalFloorNote,
              style: TextStyle(color: context.apple.labelSecondary),
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: Gaps.sm),
              ErrorText(error),
            ],
            const SizedBox(height: Gaps.md),
            FilledButton(
              onPressed: birthDate == null
                  ? null
                  : () async {
                      final heightCm = parseDecimal(height.text);
                      final weightKg = parseDecimal(weight.text);
                      final goalKcal = parseDecimal(dailyGoal.text)?.round();
                      if (heightCm == null ||
                          weightKg == null ||
                          goalKcal == null) {
                        setState(() => error = t.error('invalid_body'));
                        return;
                      }
                      try {
                        await widget.api.send(
                          'PUT',
                          '/api/profile',
                          body: {
                            'sex': sex,
                            'dateOfBirth': formatIsoDate(birthDate!),
                            'heightCm': heightCm,
                            'weightKg': weightKg,
                            'activity': activity,
                            'weeklyPace': pace,
                            'customGoalKcal': goalKcal,
                          },
                        );
                        if (mounted) setState(() => error = '');
                        await widget.onSaved();
                      } on ApiException catch (err) {
                        if (mounted) {
                          setState(() => error = t.error(err.code));
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(() => error = t.error('invalid_body'));
                        }
                      }
                    },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  List<String> operations = [];
  Map<String, bool> permissions = {};
  bool loading = true;
  String error = '';

  @override
  void initState() {
    super.initState();
    final cached = widget.api.peek('/api/rbac/permissions');
    if (cached != null) {
      operations = ((cached['operations'] as List?) ?? []).cast<String>();
      permissions = ((cached['permissions'] as Map?) ?? {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
      loading = false;
    }
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final res = await widget.api.send('GET', '/api/rbac/permissions');
      final ops = ((res['operations'] as List?) ?? []).cast<String>();
      final permsMap = ((res['permissions'] as Map?) ?? {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
      if (mounted) {
        setState(() {
          operations = ops;
          permissions = permsMap;
          loading = false;
          error = '';
        });
      }
    } on ApiException catch (err) {
      if (mounted) {
        setState(() {
          loading = false;
          error = widget.t.error(err.code);
        });
      }
    }
  }

  Future<void> toggle(String op, bool allowed) async {
    final previous = permissions[op] ?? false;
    setState(() {
      permissions[op] = allowed;
      error = '';
    });
    try {
      final res = await widget.api.send(
        'PUT',
        '/api/rbac/permissions',
        body: {
          'permissions': {op: allowed},
        },
      );
      final permsMap = ((res['permissions'] as Map?) ?? {}).map(
        (key, value) => MapEntry(key.toString(), value == true),
      );
      if (mounted) setState(() => permissions = permsMap);
    } on ApiException catch (err) {
      if (mounted) {
        setState(() {
          permissions[op] = previous;
          error = widget.t.error(err.code);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (loading) return const Center(child: CircularProgressIndicator());
    final apple = context.apple;
    return AppList(
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              t.permissions,
              style: Theme.of(context).textTheme.headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: Gaps.xs),
            Text(
              t.permissionsDesc,
              style: TextStyle(color: apple.labelSecondary),
            ),
          ],
        ),
        if (error.isNotEmpty) ErrorText(error),
        Card(
          child: Column(
            children: [
              for (var i = 0; i < operations.length; i++) ...[
                if (i > 0)
                  Divider(
                    color: apple.separator,
                    thickness: 0.5,
                    height: 0.5,
                    indent: Gaps.lg,
                  ),
                SwitchListTile.adaptive(
                  title: Text(t.operationLabel(operations[i])),
                  subtitle: Text(
                    operations[i],
                    style: TextStyle(color: apple.labelSecondary, fontSize: 12),
                  ),
                  value: permissions[operations[i]] ?? false,
                  onChanged: (value) => toggle(operations[i], value),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class FoodActions extends StatefulWidget {
  const FoodActions({
    super.key,
    required this.api,
    required this.t,
    required this.food,
    required this.admin,
    this.initialAmount = 100,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> food;
  final bool admin;
  final num initialAmount;

  @override
  State<FoodActions> createState() => _FoodActionsState();
}

class FoodPick {
  const FoodPick(this.food, this.amount);
  final Map<String, dynamic> food;
  final num amount;
}

class _FoodActionsState extends State<FoodActions> {
  late Map<String, dynamic> food = widget.food;
  late final amount = TextEditingController(
    text: _plainNumber(widget.initialAmount),
  );

  @override
  void initState() {
    super.initState();
    amount.selection = TextSelection(
      baseOffset: 0,
      extentOffset: amount.text.length,
    );
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  num? get parsedAmount {
    final value = parseDecimal(amount.text);
    return value == null || value <= 0 ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    final unit = food['basis'] == 'solid' ? t.grams : t.milliliters;
    final per100 = (food['calories'] as num?) ?? 0;
    final value = parsedAmount;
    final kcal = value == null ? 0 : (per100 * value / 100).round();
    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gaps.lg,
        0,
        Gaps.lg,
        Gaps.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        spacing: Gaps.sm,
        children: [
          Text(
            food['name'] as String,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            [
              '${_plainNumber(per100)} ${t.kcal} / 100 $unit',
              if (food['verified'] == true) t.verified,
            ].join(' · '),
            style: TextStyle(color: apple.labelSecondary),
          ),
          Row(
            spacing: Gaps.md,
            children: [
              Expanded(
                child: TextField(
                  controller: amount,
                  autofocus: true,
                  decoration: InputDecoration(labelText: '${t.amount} ($unit)'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [DecimalInputFormatter()],
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text(
                '= $kcal ${t.kcal}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: apple.accentEnergyText,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          FilledButton(
            onPressed: value == null
                ? null
                : () => Navigator.pop(context, FoodPick(food, value)),
            child: Text(t.add),
          ),
          if (food['owned'] == true)
            OutlinedButton(
              onPressed: () async {
                final path = food['published'] == true
                    ? 'unpublish'
                    : 'publish';
                final result = await widget.api.send(
                  'POST',
                  '/api/foods/${food['id']}/$path',
                );
                setState(
                  () => food = (result['food'] as Map).cast<String, dynamic>(),
                );
              },
              child: Text(food['published'] == true ? t.unpublish : t.publish),
            ),
          if (widget.admin &&
              food['published'] == true &&
              food['verified'] != true)
            OutlinedButton(
              onPressed: () async {
                final result = await widget.api.send(
                  'POST',
                  '/api/foods/${food['id']}/verify',
                );
                setState(
                  () => food = (result['food'] as Map).cast<String, dynamic>(),
                );
              },
              child: Text(t.verify),
            ),
        ],
      ),
    );
  }
}

class FastingEditor extends StatefulWidget {
  const FastingEditor({
    super.key,
    required this.t,
    required this.fasting,
    required this.onSave,
  });
  final Copy t;
  final Map<String, dynamic> fasting;
  final Future<void> Function(Map<String, dynamic> body) onSave;

  @override
  State<FastingEditor> createState() => _FastingEditorState();
}

class _FastingEditorState extends State<FastingEditor> {
  late bool enabled = widget.fasting['enabled'] == true;
  late int length = widget.fasting['lengthHours'] as int;
  late int startHour = widget.fasting['startHour'] as int;
  late Set<int> reminderOffsets = _offsetsFrom(widget.fasting['reminderOffsets']);

  static Set<int> _offsetsFrom(Object? raw) {
    if (raw is List) {
      return {
        for (final value in raw)
          if (value is int && (value == 0 || value == 30 || value == 60)) value,
      };
    }
    return {0};
  }

  void _toggleOffset(int offset, bool on) {
    setState(() {
      if (on) {
        reminderOffsets = {...reminderOffsets, offset};
      } else {
        reminderOffsets = {...reminderOffsets}..remove(offset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gaps.md,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(t.fasting),
              value: enabled,
              onChanged: (value) => setState(() => enabled = value),
            ),
            AppleMenuField<int>(
              label: t.fastingLength,
              value: length,
              options: [12, 14, 16]
                  .map((value) => AppleMenuOption(value, '$value ${t.hours}'))
                  .toList(),
              onChanged: (value) => setState(() => length = value),
            ),
            hourPicker(
              t.startHour,
              startHour,
              (value) => setState(() => startHour = value),
            ),
            Text(
              '${t.endHour}: ${((startHour + length) % 24).toString().padLeft(2, '0')}:00',
              style: TextStyle(color: apple.labelSecondary),
            ),
            if (enabled) ...[
              Text(
                t.fastReminder,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reminderAtStart),
                value: reminderOffsets.contains(0),
                onChanged: (value) => _toggleOffset(0, value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reminder30Before),
                value: reminderOffsets.contains(30),
                onChanged: (value) => _toggleOffset(30, value),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(t.reminder1HourBefore),
                value: reminderOffsets.contains(60),
                onChanged: (value) => _toggleOffset(60, value),
              ),
              Text(
                t.reminderLateNote,
                style: TextStyle(color: apple.labelSecondary, fontSize: 13),
              ),
            ],
            FilledButton(
              onPressed: () {
                final offsets = [0, 30, 60]
                    .where(reminderOffsets.contains)
                    .toList();
                widget.onSave({
                  'enabled': enabled,
                  'lengthHours': length,
                  'startHour': startHour,
                  'reminderOffsets': offsets,
                });
              },
              child: Text(t.save),
            ),
          ],
        ),
      ),
    );
  }
}

class FoodScreen extends StatefulWidget {
  const FoodScreen({
    super.key,
    required this.api,
    required this.t,
    this.barcode,
    this.initialName,
  });
  final Api api;
  final Copy t;

  /// Known when the food was scanned; otherwise the user types it.
  final String? barcode;
  final String? initialName;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  late final name = TextEditingController(text: widget.initialName ?? '');
  late final barcode = TextEditingController(text: widget.barcode ?? '');
  String basis = 'solid';
  final calories = TextEditingController();
  final protein = TextEditingController();
  final carbohydrates = TextEditingController();
  final fat = TextEditingController();
  final fiber = TextEditingController();
  final sugars = TextEditingController();
  final sodium = TextEditingController();
  String error = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.createFood)),
      body: AppList(
        gap: Gaps.md,
        children: [
          if (widget.barcode != null)
            Text(
              '${t.barcode}: ${widget.barcode}',
              style: TextStyle(color: context.apple.labelSecondary),
            )
          else
            TextField(
              controller: barcode,
              decoration: InputDecoration(
                labelText: t.barcode,
                hintText: t.optional,
              ),
              keyboardType: TextInputType.number,
            ),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: t.name),
          ),
          AppleMenuField<String>(
            label: t.measuredAs,
            value: basis,
            options: [
              AppleMenuOption('solid', t.solid),
              AppleMenuOption('liquid', t.liquid),
            ],
            onChanged: (value) => setState(() => basis = value),
          ),
          decimalField(calories, t.calories, hint: '0'),
          for (final pair in [
            [(protein, t.protein), (carbohydrates, t.carbohydrates)],
            [(fat, t.fat), (fiber, t.fiber)],
            [(sugars, t.sugars), (sodium, t.sodium)],
          ])
            Row(
              spacing: Gaps.md,
              children: [
                for (final (controller, label) in pair)
                  Expanded(
                    child: decimalField(controller, label, hint: t.optional),
                  ),
              ],
            ),
          if (error.isNotEmpty) ErrorText(error),
          FilledButton(
            onPressed: () async {
              try {
                final values = [
                  parseDecimal(calories.text),
                  ...[
                    protein.text,
                    carbohydrates.text,
                    fat.text,
                    fiber.text,
                    sugars.text,
                    sodium.text,
                  ].map(_parseOptional),
                ];
                final code = barcode.text.trim();
                if (values.any((value) => value == null)) {
                  setState(() => error = t.error('invalid_body'));
                  return;
                }
                final created = await widget.api.send(
                  'POST',
                  '/api/foods',
                  body: {
                    'barcode': code.isEmpty ? null : code,
                    'name': name.text.trim(),
                    'basis': basis,
                    'calories': values[0],
                    'protein': values[1],
                    'carbohydrates': values[2],
                    'fat': values[3],
                    'fiber': values[4],
                    'sugars': values[5],
                    'sodium': values[6],
                  },
                );
                if (context.mounted)
                  Navigator.pop(
                    context,
                    (created['food'] as Map).cast<String, dynamic>(),
                  );
              } on ApiException catch (err) {
                setState(() => error = t.error(err.code));
              }
            },
            child: Text(t.save),
          ),
        ],
      ),
    );
  }
}

Widget hourPicker(String label, int value, ValueChanged<int> onChanged) {
  return AppleMenuField<int>(
    label: label,
    value: value,
    options: [
      for (var hour = 0; hour < 24; hour++)
        AppleMenuOption(hour, '${hour.toString().padLeft(2, '0')}:00'),
    ],
    onChanged: onChanged,
  );
}

Widget decimalField(
  TextEditingController controller,
  String label, {
  ValueChanged<String>? onChanged,
  String? hint,
  String? helper,
}) {
  return TextField(
    controller: controller,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      hintText: hint,
      helperText: helper,
    ),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    inputFormatters: const [DecimalInputFormatter()],
  );
}

class DecimalInputFormatter extends TextInputFormatter {
  const DecimalInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final text = newValue.text.replaceAll(',', '.');
    if (text.isEmpty || RegExp(r'^\d*\.?\d*$').hasMatch(text)) {
      return TextEditingValue(text: text, selection: newValue.selection);
    }
    return oldValue;
  }
}

num? parseDecimal(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text)) return null;
  return num.tryParse(text);
}

/// 100 -> "100", 97.5 -> "97.5" (no trailing ".0").
String _plainNumber(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  return value.toString();
}

/// Empty optional nutrient fields count as 0.
num? _parseOptional(String raw) => raw.trim().isEmpty ? 0 : parseDecimal(raw);

String _fastLength(Map session) {
  final minutes = session['durationMinutes'];
  if (minutes is! num) return '${session['lengthHours']}h';
  final hours = minutes ~/ 60;
  final rest = (minutes % 60).toInt().toString().padLeft(2, '0');
  return '${hours}h ${rest}m';
}

String _fastEnd(Map session, String approximate) {
  final running = session['running'] == true;
  final iso = (running ? session['endsAt'] : session['endedAt']) as String?;
  if (iso == null) return '—';
  final started = _jerusalem(session['startedAt'] as String);
  final ended = _jerusalem(iso);
  final time = _padClock(ended);
  final sameDay =
      started.year == ended.year &&
      started.month == ended.month &&
      started.day == ended.day;
  final label = sameDay ? time : '$time · ${_padDate(ended)}';
  return running ? '$label $approximate' : label;
}

tz.TZDateTime _jerusalem(String iso) {
  return tz.TZDateTime.from(
    DateTime.parse(iso),
    tz.getLocation('Asia/Jerusalem'),
  );
}

String _jerusalemTime(String iso) => _padClock(_jerusalem(iso));

String _jerusalemDate(String iso) => _padDate(_jerusalem(iso));

String _padClock(tz.TZDateTime time) {
  return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
}

String _padDate(tz.TZDateTime time) {
  final day = time.day.toString().padLeft(2, '0');
  final month = time.month.toString().padLeft(2, '0');
  return '$day/$month/${time.year}';
}

String _clock(Duration duration) {
  final positive = duration.isNegative ? Duration.zero : duration;
  final hours = positive.inHours.toString().padLeft(2, '0');
  final minutes = positive.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = positive.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$hours:$minutes:$seconds';
}

String _shift(String day, int count) {
  final date = DateTime.parse('${day}T00:00:00Z').add(Duration(days: count));
  final month = date.month.toString().padLeft(2, '0');
  final dayText = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$dayText';
}

class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 320),
  });
  final Widget child;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        alignment: Alignment.topCenter,
        children: [...previous, ?current],
      ),
      child: child,
    );
  }
}

class FadeIn extends StatefulWidget {
  const FadeIn({super.key, required this.child});
  final Widget child;

  @override
  State<FadeIn> createState() => _FadeInState();
}

class _FadeInState extends State<FadeIn> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  );
  late final CurvedAnimation opacity = CurvedAnimation(
    parent: controller,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void dispose() {
    opacity.dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(opacity: opacity, child: widget.child);
  }
}

class EaseBuilder extends StatefulWidget {
  const EaseBuilder({
    super.key,
    required this.value,
    required this.builder,
    this.from,
    this.duration = const Duration(milliseconds: 700),
  });
  final double value;
  final double? from;
  final Duration duration;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<EaseBuilder> createState() => _EaseBuilderState();
}

class _EaseBuilderState extends State<EaseBuilder>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  late double _from;
  late double _to;

  bool get _reduce => WidgetsBinding
      .instance
      .platformDispatcher
      .accessibilityFeatures
      .disableAnimations;

  @override
  void initState() {
    super.initState();
    _to = widget.value;
    _from = widget.from ?? widget.value;
    if (_reduce || _from == _to) {
      _from = _to;
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(EaseBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.duration;
    if (oldWidget.value == widget.value) return;
    _from = _shown;
    _to = widget.value;
    if (_reduce || _from == _to) {
      _from = _to;
      _controller.value = 1;
      return;
    }
    _controller.forward(from: 0);
  }

  double get _shown {
    final t = Curves.easeOutCubic.transform(_controller.value);
    return _from + (_to - _from) * t;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => widget.builder(context, _shown),
    );
  }
}

/// Whole number with thousands separators: 1603.4 -> "1,603", -1234 -> "-1,234".
String _grouped(num value) {
  final rounded = value.round();
  if (rounded < 0) return '-${_grouped(-rounded)}';
  final digits = rounded.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

class HealthProgressRow extends StatelessWidget {
  const HealthProgressRow({
    super.key,
    required this.label,
    required this.value,
    required this.goal,
    this.unit = '',
  });
  final String label;
  final num value;
  final num goal;
  final String unit;

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    final ratio = goal > 0 ? (value / goal).clamp(0, 1).toDouble() : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(color: apple.labelSecondary)),
            Text(
              '${_grouped(value)} / ${_grouped(goal)}${unit.isEmpty ? '' : ' $unit'}',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: Gaps.sm),
        EaseBuilder(
          from: 0,
          value: ratio,
          builder: (context, shown) => ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: shown,
              minHeight: 8,
              backgroundColor: apple.tertiaryFill,
              color: ratio >= 1 ? apple.accentSuccess : apple.accentPrimary,
            ),
          ),
        ),
      ],
    );
  }
}

class AnimatedWeightChart extends StatefulWidget {
  const AnimatedWeightChart({super.key, required this.weights});
  final List<Map<String, dynamic>> weights;

  @override
  State<AnimatedWeightChart> createState() => _AnimatedWeightChartState();
}

class _AnimatedWeightChartState extends State<AnimatedWeightChart>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding
        .instance
        .platformDispatcher
        .accessibilityFeatures
        .disableAnimations) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedWeightChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weights.length != widget.weights.length &&
        !WidgetsBinding
            .instance
            .platformDispatcher
            .accessibilityFeatures
            .disableAnimations) {
      controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => CustomPaint(
        painter: WeightPainter(
          widget.weights,
          Curves.easeOutCubic.transform(controller.value),
          context.apple.accentPrimary,
          context.apple.accentSuccess,
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}
