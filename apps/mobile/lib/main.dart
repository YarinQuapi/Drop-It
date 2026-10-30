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
    }
  }

  Future<void> boot() async {
    themeMode = await api.loadThemeMode();
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
      await reminders.schedule(
        enabled: fasting['enabled'] == true,
        startHour: fasting['startHour'] as int,
        endHour: fasting['endHour'] as int,
        startText: t.reminderStart,
        endText: t.reminderEnd,
        doneText: t.reminderDone,
        endsAtIso: fasting['endsAt'] as String?,
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
  });
  final Api api;
  final Copy t;
  final Future<void> Function(Map<String, dynamic>) onAuth;

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
    final language = Localizations.localeOf(context).languageCode == 'he'
        ? 'he'
        : 'en';
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
              decoration: InputDecoration(labelText: t.email),
              keyboardType: TextInputType.emailAddress,
            ),
            TextField(
              controller: password,
              decoration: InputDecoration(labelText: t.password),
              obscureText: true,
              onChanged: (_) {
                if (signup) setState(() {});
              },
            ),
            if (signup) ...[
              TextField(
                controller: confirmPassword,
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
          ],
        ),
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
  String sex = 'female';
  DateTime? birthDate;
  final height = TextEditingController();
  final weight = TextEditingController();
  String activity = 'sedentary';
  String pace = 'kg050';
  bool profileStep = false;
  String error = '';

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
                Text(
                  t.fastingQuestion,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Row(
                  children: [
                    Expanded(
                      child: wants == true
                          ? FilledButton(
                              onPressed: () => setState(() => wants = true),
                              child: Text(t.yes),
                            )
                          : OutlinedButton(
                              onPressed: () => setState(() => wants = true),
                              child: Text(t.yes),
                            ),
                    ),
                    const SizedBox(width: Gaps.sm),
                    Expanded(
                      child: wants == false
                          ? FilledButton(
                              onPressed: () => setState(() => wants = false),
                              child: Text(t.no),
                            )
                          : OutlinedButton(
                              onPressed: () => setState(() => wants = false),
                              child: Text(t.no),
                            ),
                    ),
                  ],
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
                Text(
                  t.profileTitle,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                AppleMenuField<String>(
                  label: t.sex,
                  value: sex,
                  options: [
                    AppleMenuOption('female', t.female),
                    AppleMenuOption('male', t.male),
                  ],
                  onChanged: (value) => setState(() => sex = value),
                ),
                AppleDateField(
                  label: t.dateOfBirth,
                  value: birthDate,
                  doneLabel: t.done,
                  onChanged: (value) => setState(() => birthDate = value),
                ),
                decimalField(height, t.height),
                decimalField(weight, t.weightKg),
                AppleMenuField<String>(
                  label: t.activity,
                  value: activity,
                  options: ['sedentary', 'light', 'moderate', 'very', 'extra']
                      .map(
                        (value) =>
                            AppleMenuOption(value, t.activityLabel(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => activity = value),
                ),
                AppleMenuField<String>(
                  label: t.pace,
                  value: pace,
                  options: ['kg025', 'kg050', 'kg100']
                      .map(
                        (value) => AppleMenuOption(value, t.paceLabel(value)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => pace = value),
                ),
                if (error.isNotEmpty) ErrorText(error),
                FilledButton(
                  onPressed: birthDate == null
                      ? null
                      : () async {
                          final heightCm = parseDecimal(height.text);
                          final weightKg = parseDecimal(weight.text);
                          if (heightCm == null || weightKg == null) {
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

  void openPage(int value) {
    setState(() => index = value);
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final isAdmin = widget.me['user']['isAdmin'] == true;
    final perms = ((widget.me['permissions'] as List?) ?? []).cast<String>();
    final canVerifyFoods = isAdmin || perms.contains('foods:verify');
    final pages = [
      TodayScreen(
        api: widget.api,
        t: t,
        admin: canVerifyFoods,
        sync: widget.sync,
      ),
      WeekScreen(api: widget.api, t: t),
      WeightScreen(api: widget.api, t: t),
      FastingScreen(api: widget.api, t: t),
      SettingsScreen(
        api: widget.api,
        t: t,
        me: widget.me,
        themeMode: widget.themeMode,
        onThemeMode: widget.onThemeMode,
        onMe: widget.onMe,
        health: widget.health,
        sync: widget.sync,
      ),
      if (isAdmin) PermissionsScreen(api: widget.api, t: t),
    ];
    final items = [
      t.today,
      t.week,
      t.weight,
      t.fasting,
      t.settings,
      if (isAdmin) t.permissions,
    ];
    final safeIndex = index < pages.length ? index : 0;
    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Gaps.sm),
            children: [
              for (var i = 0; i < items.length; i++)
                ListTile(
                  minTileHeight: Gaps.hit,
                  selected: i == safeIndex,
                  selectedColor: context.apple.accentPrimary,
                  selectedTileColor: context.apple.accentTint,
                  title: Text(
                    items[i],
                    style: TextStyle(
                      fontWeight: i == safeIndex
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                  onTap: () => openPage(i),
                ),
              ListTile(
                minTileHeight: Gaps.hit,
                title: Text(
                  t.logout,
                  style: TextStyle(
                    color: context.apple.accentDangerText,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                onTap: widget.onLogout,
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: t.menu,
            onPressed: () {
              final scaffold = Scaffold.of(context);
              if (scaffold.isDrawerOpen) {
                Navigator.of(context).pop();
              } else {
                scaffold.openDrawer();
              }
            },
            icon: const Icon(Icons.menu),
          ),
        ),
        title: Text(t.appName),
      ),
      body: SoftSwitcher(
        child: KeyedSubtree(key: ValueKey(safeIndex), child: pages[safeIndex]),
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
  Map<String, dynamic>? day;
  String error = '';
  String? loggingMeal;

  @override
  void initState() {
    super.initState();
    AppleHealth.synced.addListener(_onHealthSynced);
    unawaited(load());
  }

  @override
  void dispose() {
    AppleHealth.synced.removeListener(_onHealthSynced);
    super.dispose();
  }

  void _onHealthSynced() {
    if (mounted) unawaited(load());
  }

  Future<void> load() async {
    try {
      final nextDay = await widget.api.send('GET', '/api/days/today');
      if (!mounted) return;
      setState(() {
        day = nextDay;
        error = '';
      });
    } on ApiException catch (err) {
      if (!mounted) return;
      setState(() => error = widget.t.error(err.code));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final totals = (day?['totals'] as Map?)?.cast<String, dynamic>();
    final entries = ((day?['entries'] as List?) ?? []).cast<Map>();
    final goal = (day?['goalKcal'] as num?) ?? 0;
    final eaten = (totals?['calories'] as num?) ?? 0;
    final remaining = goal - eaten;
    final over = eaten > goal;
    final apple = context.apple;
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
              child: Row(
                children: [
                  SizedBox(
                    width: 132,
                    height: 132,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        EaseBuilder(
                          from: 0,
                          value: goal == 0
                              ? 0
                              : (eaten / goal).clamp(0, 1).toDouble(),
                          builder: (context, value) =>
                              CircularProgressIndicator(
                                value: value,
                                strokeWidth: 10,
                                strokeCap: StrokeCap.round,
                                backgroundColor: apple.tertiaryFill,
                                color: over
                                    ? apple.accentDanger
                                    : apple.accentEnergy,
                              ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EaseBuilder(
                              from: goal.toDouble(),
                              value: remaining.toDouble(),
                              builder: (context, value) => Text(
                                '${value.round()}',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
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
                        Text(
                          t.today,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: Gaps.xs),
                        if (day!['healthAdjusted'] == true) ...[
                          Text(
                            '${t.healthBaseGoal}  ${day!['baseGoalKcal']} ${t.kcal}',
                          ),
                          Text(
                            '${t.healthActiveKcal}  +${day!['activeKcal']} ${t.kcal}',
                          ),
                        ],
                        Text('${t.goal}  $goal ${t.kcal}'),
                        Text('${t.eaten}  $eaten ${t.kcal}'),
                        const SizedBox(height: Gaps.xs),
                        Text(
                          over
                              ? t.missed
                              : day!['success'] == true
                              ? t.success
                              : day!['healthAdjusted'] == true
                              ? t.healthEstimate
                              : t.estimate,
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
            ),
          ),
        if (day != null && day!['healthSynced'] == true)
          Card(
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
              ),
            ),
          ),
        if (error.isNotEmpty && loggingMeal == null) ErrorText(error),
        for (final meal in _meals) ...[
          _MealCard(
            t: t,
            meal: meal,
            entries: entries
                .where(
                  (entry) => (entry['meal'] as String? ?? 'snacks') == meal,
                )
                .toList(),
            logging: loggingMeal == meal,
            onToggleLog: () =>
                setState(() => loggingMeal = loggingMeal == meal ? null : meal),
            onScan: () async {
              final code = await Navigator.push<String>(
                context,
                MaterialPageRoute(builder: (_) => const ScanScreen()),
              );
              if (code != null) await lookup(code, meal);
            },
            onLookup: () async {
              final code = await askText(context, t.barcode);
              if (code != null && code.isNotEmpty) await lookup(code, meal);
            },
            onDelete: (id) async {
              await widget.api.send('DELETE', '/api/days/today/entries/$id');
              await load();
            },
          ),
        ],
      ],
    );
  }

  Future<void> lookup(String barcode, String meal) async {
    final t = widget.t;
    final result = await widget.api.send(
      'GET',
      '/api/foods/barcode/${Uri.encodeComponent(barcode)}',
    );
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
    food = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) =>
          FoodActions(api: widget.api, t: t, food: food!, admin: widget.admin),
    );
    if (food == null || !mounted) return;
    final amount = await askText(
      context,
      '${t.amount} (${food['basis'] == 'solid' ? t.grams : t.milliliters})',
    );
    if (amount == null) return;
    try {
      await widget.api.send(
        'POST',
        '/api/days/today/entries',
        body: {'foodId': food['id'], 'amount': num.parse(amount), 'meal': meal},
      );
      setState(() => loggingMeal = null);
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
    required this.logging,
    required this.onToggleLog,
    required this.onScan,
    required this.onLookup,
    required this.onDelete,
  });

  final Copy t;
  final String meal;
  final List<Map> entries;
  final bool logging;
  final VoidCallback onToggleLog;
  final Future<void> Function() onScan;
  final Future<void> Function() onLookup;
  final Future<void> Function(String id) onDelete;

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
                  '$mealKcal ${t.kcal}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: apple.accentEnergyText,
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
                          '${entry['calories']}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.delete_outline,
                            color: apple.accentDangerText,
                          ),
                          onPressed: () => onDelete(entry['id'] as String),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: Gaps.md),
            logging
                ? OutlinedButton(onPressed: onToggleLog, child: Text(t.log))
                : FilledButton(onPressed: onToggleLog, child: Text(t.log)),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 280),
              sizeCurve: Curves.easeOutCubic,
              crossFadeState: logging
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: Gaps.sm),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onScan,
                        child: Text(t.scan),
                      ),
                    ),
                    const SizedBox(width: Gaps.sm),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onLookup,
                        child: Text(t.lookUp),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool done = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: MobileScanner(
        onDetect: (capture) {
          if (done) return;
          final value = capture.barcodes.isEmpty
              ? null
              : capture.barcodes.first.rawValue;
          if (value == null || value.isEmpty) return;
          done = true;
          Navigator.pop(context, value);
        },
      ),
    );
  }
}

class FastingScreen extends StatefulWidget {
  const FastingScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<FastingScreen> createState() => _FastingScreenState();
}

class _FastingScreenState extends State<FastingScreen> {
  Map<String, dynamic>? fasting;
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
                  const SizedBox(height: Gaps.sm),
                  Text(
                    _clock(left),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 52,
                      fontWeight: FontWeight.w300,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
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
  Map<String, dynamic>? week;
  String? on;

  @override
  void initState() {
    super.initState();
    unawaited(load());
  }

  Future<void> load() async {
    final query = on == null ? '' : '?on=$on';
    final data = await widget.api.send('GET', '/api/weeks$query');
    setState(() => week = data);
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    if (week == null) return const Center(child: CircularProgressIndicator());
    final days = (week!['days'] as List)
        .cast<Map>()
        .where(
          (day) =>
              day['future'] != true && ((day['calories'] as num?) ?? 0) > 0,
        )
        .toList();
    final apple = context.apple;
    return FadeIn(
      key: ValueKey(week!['sunday']),
      child: AppList(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    on = _shift(week!['sunday'] as String, -7);
                    load();
                  },
                  child: Text(t.previousWeek),
                ),
              ),
              const SizedBox(width: Gaps.sm),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    on = _shift(week!['sunday'] as String, 7);
                    load();
                  },
                  child: Text(t.nextWeek),
                ),
              ),
            ],
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(Gaps.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${t.calorieIntake}: ${week!['calorieIntake']} / ${week!['goalKcal']}',
                  ),
                  const SizedBox(height: Gaps.xs),
                  Text('${t.successCount}: ${week!['successCount']}'),
                  const SizedBox(height: Gaps.xs),
                  Text(
                    '${t.weightChange}: ${week!['weightChangeKg'] ?? t.noWeightChange}',
                    style: TextStyle(color: apple.labelSecondary),
                  ),
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
                      title: Text(days[i]['day'] as String),
                      subtitle: Text(
                        [
                          '${days[i]['calories']} / ${days[i]['goalKcal']}',
                          if (days[i]['steps'] != null)
                            '${t.healthSteps} ${_grouped(days[i]['steps'] as num)} · ${t.healthExercise} ${days[i]['exerciseMinutes'] ?? 0} ${t.healthMinutes}'
                                '${((days[i]['activeKcal'] as num?) ?? 0) > 0 ? ' · ${t.healthActiveKcal} +${days[i]['activeKcal']} ${t.kcal}' : ''}',
                        ].join('\n'),
                        style: TextStyle(color: apple.labelSecondary),
                      ),
                      trailing: Text(
                        days[i]['success'] == true ? t.success : t.missed,
                        style: TextStyle(color: apple.labelSecondary),
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

class WeightScreen extends StatefulWidget {
  const WeightScreen({super.key, required this.api, required this.t});
  final Api api;
  final Copy t;

  @override
  State<WeightScreen> createState() => _WeightScreenState();
}

class _WeightScreenState extends State<WeightScreen> {
  List<Map<String, dynamic>> weights = [];
  final controller = TextEditingController();

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
                TextField(
                  controller: controller,
                  decoration: InputDecoration(labelText: t.weightKg),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: Gaps.md),
                FilledButton(
                  onPressed: () async {
                    await widget.api.send(
                      'POST',
                      '/api/weights',
                      body: {'weightKg': num.parse(controller.text)},
                    );
                    controller.clear();
                    await load();
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
                      '${point['loggedAt']} · ${point['source'] == 'health' ? t.healthSource : t.manualSource}',
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
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final String themeMode;
  final ValueChanged<String> onThemeMode;
  final ValueChanged<Map<String, dynamic>> onMe;
  final AppleHealth health;
  final Future<void> Function() sync;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? profile;
  Map<String, dynamic>? fasting;
  Map<String, dynamic>? healthState;
  final stepGoal = TextEditingController();
  final exerciseGoal = TextEditingController();
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
                    decoration: InputDecoration(labelText: t.currentPassword),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gaps.md),
                  TextField(
                    controller: newPassword,
                    decoration: InputDecoration(labelText: t.newPassword),
                    obscureText: true,
                    onChanged: (_) => setState(() {}),
                  ),
                  const SizedBox(height: Gaps.md),
                  TextField(
                    controller: confirmPassword,
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
        if (fasting != null)
          FastingEditor(
            t: t,
            fasting: fasting!,
            onSave: (body) async {
              await widget.api.send('PUT', '/api/fasting', body: body);
              await load();
              await widget.sync();
            },
          ),
        if (healthState != null) _healthCard(context),
        if (profile != null)
          Text(
            '${t.weightKg}: ${profile!['weightKg']} · ${t.goal}',
            style: TextStyle(color: apple.labelSecondary),
          ),
      ],
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
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> food;
  final bool admin;

  @override
  State<FoodActions> createState() => _FoodActionsState();
}

class _FoodActionsState extends State<FoodActions> {
  late Map<String, dynamic> food = widget.food;

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
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
          if (food['verified'] == true)
            Text(
              t.verified,
              style: TextStyle(color: context.apple.accentSuccessText),
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
          FilledButton(
            onPressed: () => Navigator.pop(context, food),
            child: Text(t.add),
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

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
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
              style: TextStyle(color: context.apple.labelSecondary),
            ),
            FilledButton(
              onPressed: () => widget.onSave({
                'enabled': enabled,
                'lengthHours': length,
                'startHour': startHour,
              }),
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
    required this.barcode,
  });
  final Api api;
  final Copy t;
  final String barcode;

  @override
  State<FoodScreen> createState() => _FoodScreenState();
}

class _FoodScreenState extends State<FoodScreen> {
  final name = TextEditingController();
  String basis = 'solid';
  final calories = TextEditingController(text: '0');
  final protein = TextEditingController(text: '0');
  final carbohydrates = TextEditingController(text: '0');
  final fat = TextEditingController(text: '0');
  final fiber = TextEditingController(text: '0');
  final sugars = TextEditingController(text: '0');
  final sodium = TextEditingController(text: '0');
  String error = '';

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      appBar: AppBar(title: Text(t.createFood)),
      body: AppList(
        gap: Gaps.md,
        children: [
          Text(
            '${t.barcode}: ${widget.barcode}',
            style: TextStyle(color: context.apple.labelSecondary),
          ),
          TextField(
            controller: name,
            decoration: InputDecoration(labelText: t.name),
          ),
          AppleMenuField<String>(
            value: basis,
            options: [
              AppleMenuOption('solid', t.solid),
              AppleMenuOption('liquid', t.liquid),
            ],
            onChanged: (value) => setState(() => basis = value),
          ),
          decimalField(calories, t.calories),
          decimalField(protein, t.protein),
          decimalField(carbohydrates, t.carbohydrates),
          decimalField(fat, t.fat),
          decimalField(fiber, t.fiber),
          decimalField(sugars, t.sugars),
          decimalField(sodium, t.sodium),
          if (error.isNotEmpty) ErrorText(error),
          FilledButton(
            onPressed: () async {
              try {
                final values = [
                  calories.text,
                  protein.text,
                  carbohydrates.text,
                  fat.text,
                  fiber.text,
                  sugars.text,
                  sodium.text,
                ].map(parseDecimal).toList();
                if (values.any((value) => value == null)) {
                  setState(() => error = t.error('invalid_body'));
                  return;
                }
                final created = await widget.api.send(
                  'POST',
                  '/api/foods',
                  body: {
                    'barcode': widget.barcode,
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

Widget decimalField(TextEditingController controller, String label) {
  return TextField(
    controller: controller,
    decoration: InputDecoration(labelText: label),
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

Future<String?> askText(BuildContext context, String label) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: TextInputType.number,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text.trim()),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}

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

String _grouped(num value) {
  final digits = value.round().toString();
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
