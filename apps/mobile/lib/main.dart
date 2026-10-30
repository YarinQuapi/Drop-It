import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:timezone/timezone.dart' as tz;

import 'api.dart';
import 'copy.dart';
import 'reminders.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const DropItApp());
}

class DropItApp extends StatefulWidget {
  const DropItApp({super.key});

  @override
  State<DropItApp> createState() => _DropItAppState();
}

class _DropItAppState extends State<DropItApp> {
  final Api api = Api();
  final Reminders reminders = Reminders();
  Map<String, dynamic>? me;
  bool loading = true;
  String lang = 'en';

  Copy get t => Copy(lang);

  @override
  void initState() {
    super.initState();
    unawaited(boot());
  }

  Future<void> boot() async {
    await reminders.init();
    await api.loadToken();
    if (api.token != null) {
      try {
        me = await api.send('GET', '/api/auth/me');
        lang = me!['user']['language'] as String;
      } catch (_) {
        await api.setToken(null);
      }
    }
    if (mounted) setState(() => loading = false);
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
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final copy = t;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: copy.appName,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFE07A2F),
          onPrimary: Color(0xFF1A120C),
          surface: Color(0xFF1C1C1F),
          onSurface: Color(0xFFF3F0EC),
          secondary: Color(0xFFC45C16),
        ),
        cardTheme: const CardThemeData(
          color: Color(0xFF1C1C1F),
          elevation: 0,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Color(0xFFF3F0EC),
        ),
        navigationBarTheme: const NavigationBarThemeData(
          backgroundColor: Color(0xFF121214),
          indicatorColor: Color(0xFF8C3D12),
        ),
        pageTransitionsTheme: const PageTransitionsTheme(
          builders: {
            TargetPlatform.android: SoftPageTransitionsBuilder(),
            TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
            TargetPlatform.linux: SoftPageTransitionsBuilder(),
            TargetPlatform.windows: SoftPageTransitionsBuilder(),
            TargetPlatform.fuchsia: SoftPageTransitionsBuilder(),
          },
        ),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF121214),
        ),
      ),
      builder: (context, child) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF8C3D12), Color(0xFF3A2418), Color(0xFF121214)],
              stops: [0, 0.32, 0.68],
            ),
          ),
          child: child,
        );
      },
      home: Directionality(
        textDirection: lang == 'he' ? TextDirection.rtl : TextDirection.ltr,
        child: SoftSwitcher(
          child: loading
              ? const Scaffold(key: ValueKey('loading'), body: Center(child: CircularProgressIndicator()))
              : me == null
                  ? AuthScreen(key: const ValueKey('auth'), api: api, t: copy, onAuth: afterAuth)
                  : me!['hasProfile'] != true
                      ? SetupScreen(
                          key: const ValueKey('setup'),
                          api: api,
                          t: copy,
                          onReady: (next) => setState(() => me = next),
                          sync: syncReminders,
                        )
                      : HomeScreen(
                          key: const ValueKey('home'),
                          api: api,
                          t: copy,
                          me: me!,
                          onMe: (next) => setState(() {
                            me = next;
                            lang = next['user']['language'] as String;
                          }),
                          onLogout: () async {
                            await api.send('POST', '/api/auth/logout');
                            await api.setToken(null);
                            setState(() => me = null);
                          },
                          sync: syncReminders,
                        ),
        ),
      ),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.api, required this.t, required this.onAuth});
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
  String error = '';

  bool get _ruleLength => password.text.length >= 8 && password.text.length <= 200;
  bool get _ruleEnglish => password.text.isNotEmpty && RegExp(r'^[\x21-\x7E]+$').hasMatch(password.text);
  bool get _ruleUppercase => RegExp(r'[A-Z]').hasMatch(password.text);
  bool get _ruleNumber => RegExp(r'[0-9]').hasMatch(password.text);
  bool get _ruleSymbol => RegExp(r'[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]').hasMatch(password.text);
  bool get _ruleMatch => password.text.isNotEmpty && password.text == confirmPassword.text;
  bool get _signupValid => _ruleLength && _ruleEnglish && _ruleUppercase && _ruleNumber && _ruleSymbol && _ruleMatch;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Widget _ruleRow(bool ok, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${ok ? '✓' : '○'} $label',
        style: TextStyle(color: ok ? const Color(0xFF8FD9A8) : const Color(0xFFB7B1AA), fontSize: 13),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                signup ? t.signup : t.login,
                key: ValueKey(signup),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            TextField(controller: email, decoration: InputDecoration(labelText: t.email), keyboardType: TextInputType.emailAddress),
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
              const SizedBox(height: 10),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.passwordRulesTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      _ruleRow(_ruleLength, t.ruleLength),
                      _ruleRow(_ruleEnglish, t.ruleEnglish),
                      _ruleRow(_ruleUppercase, t.ruleUppercase),
                      _ruleRow(_ruleNumber, t.ruleNumber),
                      _ruleRow(_ruleSymbol, t.ruleSymbol),
                      _ruleRow(_ruleMatch, t.ruleMatch),
                    ],
                  ),
                ),
              ),
            ],
            if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
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
                                'language': Localizations.localeOf(context).languageCode == 'he' ? 'he' : 'en',
                              }
                            : {
                                'email': email.text.trim(),
                                'password': password.text,
                              };
                        final auth = await widget.api.send('POST', signup ? '/api/auth/signup' : '/api/auth/login', body: body);
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
  const SetupScreen({super.key, required this.api, required this.t, required this.onReady, required this.sync});
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
  final dob = TextEditingController();
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
          child: ListView(
          key: ValueKey(profileStep),
          padding: const EdgeInsets.all(20),
          children: [
            if (!profileStep) ...[
              Text(t.fastingQuestion, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 12),
              Row(children: [
                FilledButton(onPressed: () => setState(() => wants = true), child: Text(t.yes)),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => setState(() => wants = false), child: Text(t.no)),
              ]),
              AnimatedCrossFade(
                duration: const Duration(milliseconds: 280),
                sizeCurve: Curves.easeOutCubic,
                crossFadeState: wants == true ? CrossFadeState.showSecond : CrossFadeState.showFirst,
                firstChild: const SizedBox(width: double.infinity),
                secondChild: Column(
                  children: [
                    DropdownButtonFormField<int>(
                      initialValue: length,
                      decoration: InputDecoration(labelText: t.fastingLength),
                      items: [12, 14, 16].map((value) => DropdownMenuItem(value: value, child: Text('$value ${t.hours}'))).toList(),
                      onChanged: (value) => setState(() => length = value ?? 16),
                    ),
                    hourPicker(t.startHour, startHour, (value) => setState(() => startHour = value)),
                    Text('${t.endHour}: ${((startHour + length) % 24).toString().padLeft(2, '0')}:00'),
                  ],
                ),
              ),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: wants == null
                    ? null
                    : () async {
                        try {
                          await widget.api.send('PUT', '/api/fasting', body: {
                            'enabled': wants == true,
                            'lengthHours': length,
                            'startHour': startHour,
                          });
                          await widget.sync();
                          setState(() => profileStep = true);
                        } on ApiException catch (err) {
                          setState(() => error = t.error(err.code));
                        }
                      },
                child: Text(t.continueLabel),
              ),
            ] else ...[
              Text(t.profileTitle, style: Theme.of(context).textTheme.headlineSmall),
              DropdownButtonFormField<String>(
                initialValue: sex,
                decoration: InputDecoration(labelText: t.sex),
                items: [DropdownMenuItem(value: 'female', child: Text(t.female)), DropdownMenuItem(value: 'male', child: Text(t.male))],
                onChanged: (value) => setState(() => sex = value ?? 'female'),
              ),
              TextField(controller: dob, decoration: InputDecoration(labelText: '${t.dateOfBirth} (YYYY-MM-DD)')),
              TextField(controller: height, decoration: InputDecoration(labelText: t.height), keyboardType: TextInputType.number),
              TextField(controller: weight, decoration: InputDecoration(labelText: t.weightKg), keyboardType: TextInputType.number),
              DropdownButtonFormField<String>(
                initialValue: activity,
                decoration: InputDecoration(labelText: t.activity),
                items: ['sedentary', 'light', 'moderate', 'very', 'extra']
                    .map((value) => DropdownMenuItem(value: value, child: Text(t.activityLabel(value))))
                    .toList(),
                onChanged: (value) => setState(() => activity = value ?? 'sedentary'),
              ),
              DropdownButtonFormField<String>(
                initialValue: pace,
                decoration: InputDecoration(labelText: t.pace),
                items: ['kg025', 'kg050', 'kg100'].map((value) => DropdownMenuItem(value: value, child: Text(t.paceLabel(value)))).toList(),
                onChanged: (value) => setState(() => pace = value ?? 'kg050'),
              ),
              if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
              FilledButton(
                onPressed: () async {
                  try {
                    await widget.api.send('PUT', '/api/profile', body: {
                      'sex': sex,
                      'dateOfBirth': dob.text.trim(),
                      'heightCm': num.parse(height.text),
                      'weightKg': num.parse(weight.text),
                      'activity': activity,
                      'weeklyPace': pace,
                    });
                    widget.onReady(await widget.api.send('GET', '/api/auth/me'));
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
    required this.onMe,
    required this.onLogout,
    required this.sync,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final ValueChanged<Map<String, dynamic>> onMe;
  final Future<void> Function() onLogout;
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
      TodayScreen(api: widget.api, t: t, admin: canVerifyFoods, sync: widget.sync),
      WeekScreen(api: widget.api, t: t),
      WeightScreen(api: widget.api, t: t),
      FastingScreen(api: widget.api, t: t),
      SettingsScreen(api: widget.api, t: t, me: widget.me, onMe: widget.onMe, sync: widget.sync),
      if (isAdmin) PermissionsScreen(api: widget.api, t: t),
    ];
    final items = [t.today, t.week, t.weight, t.fasting, t.settings, if (isAdmin) t.permissions];
    final safeIndex = index < pages.length ? index : 0;
    return Scaffold(
      drawer: Drawer(
        backgroundColor: const Color(0xFF1C1C1F),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              for (var i = 0; i < items.length; i++)
                ListTile(
                  title: Text(items[i], style: TextStyle(color: i == safeIndex ? const Color(0xFFE07A2F) : null, fontWeight: FontWeight.w700)),
                  onTap: () => openPage(i),
                ),
              ListTile(title: Text(t.logout), onTap: widget.onLogout),
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
  const TodayScreen({super.key, required this.api, required this.t, required this.admin, required this.sync});
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
    unawaited(load());
  }

  Future<void> load() async {
    try {
      final nextDay = await widget.api.send('GET', '/api/days/today');
      setState(() {
        day = nextDay;
        error = '';
      });
    } on ApiException catch (err) {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (day != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                          value: goal == 0 ? 0 : (eaten / goal).clamp(0, 1).toDouble(),
                          builder: (context, value) => CircularProgressIndicator(
                            value: value,
                            strokeWidth: 10,
                            strokeCap: StrokeCap.round,
                            backgroundColor: const Color(0xFF2E2E32),
                            color: over ? const Color(0xFFFF8A7A) : const Color(0xFFE07A2F),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            EaseBuilder(
                              from: goal.toDouble(),
                              value: remaining.toDouble(),
                              builder: (context, value) => Text('${value.round()}', style: Theme.of(context).textTheme.headlineMedium),
                            ),
                            Text(t.remaining),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(t.today, style: Theme.of(context).textTheme.titleLarge),
                        Text('${t.goal}  $goal ${t.kcal}'),
                        Text('${t.eaten}  $eaten ${t.kcal}'),
                        Text(over ? t.missed : day!['success'] == true ? t.success : t.estimate),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (error.isNotEmpty && loggingMeal == null) Text(error, style: const TextStyle(color: Colors.red)),
        for (final meal in _meals) ...[
          const SizedBox(height: 8),
          _MealCard(
            t: t,
            meal: meal,
            entries: entries.where((entry) => (entry['meal'] as String? ?? 'snacks') == meal).toList(),
            logging: loggingMeal == meal,
            onToggleLog: () => setState(() => loggingMeal = loggingMeal == meal ? null : meal),
            onScan: () async {
              final code = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const ScanScreen()));
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
    final result = await widget.api.send('GET', '/api/foods/barcode/${Uri.encodeComponent(barcode)}');
    if (!mounted) return;
    Map<String, dynamic>? food = (result['food'] as Map?)?.cast<String, dynamic>();
    if (result['status'] == 'none') {
      food = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute(builder: (_) => FoodScreen(api: widget.api, t: t, barcode: barcode)),
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
                onTap: () => Navigator.pop(context, item.cast<String, dynamic>()),
              ),
          ],
        ),
      );
    }
    if (food == null || !mounted) return;
    food = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      builder: (context) => FoodActions(api: widget.api, t: t, food: food!, admin: widget.admin),
    );
    if (food == null || !mounted) return;
    final amount = await askText(context, '${t.amount} (${food['basis'] == 'solid' ? t.grams : t.milliliters})');
    if (amount == null) return;
    try {
      await widget.api.send('POST', '/api/days/today/entries', body: {
        'foodId': food['id'],
        'amount': num.parse(amount),
        'meal': meal,
      });
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
    final mealKcal = entries.fold<num>(0, (sum, entry) => sum + ((entry['calories'] as num?) ?? 0));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: Text(t.mealLabel(meal), style: Theme.of(context).textTheme.titleMedium)),
                Text('$mealKcal ${t.kcal}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFFF0A36A))),
              ],
            ),
            if (entries.isEmpty) Padding(padding: const EdgeInsets.only(top: 4, bottom: 8), child: Text(t.emptyMeal, style: Theme.of(context).textTheme.bodySmall)),
            for (final entry in entries)
              FadeIn(
                key: ValueKey(entry['id']),
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry['name'] as String),
                  subtitle: Text('${entry['amount']} ${entry['basis'] == 'solid' ? t.grams : t.milliliters}'),
                  trailing: SizedBox(
                    width: 116,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text('${entry['calories']}', style: const TextStyle(fontWeight: FontWeight.w700)),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => onDelete(entry['id'] as String),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            FilledButton(
              style: logging ? FilledButton.styleFrom(backgroundColor: const Color(0xFF2A2420)) : null,
              onPressed: onToggleLog,
              child: Text(t.log),
            ),
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 280),
              sizeCurve: Curves.easeOutCubic,
              crossFadeState: logging ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              firstChild: const SizedBox(width: double.infinity),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(children: [
                  Expanded(child: OutlinedButton(onPressed: onScan, child: Text(t.scan))),
                  const SizedBox(width: 8),
                  Expanded(child: OutlinedButton(onPressed: onLookup, child: Text(t.lookUp))),
                ]),
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
          final value = capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
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
    final left = endsAt == null ? Duration.zero : DateTime.parse(endsAt).difference(DateTime.now());
    final sessions = ((fasting?['sessions'] as List?) ?? []).cast<Map>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: running ? const Color(0xFF8C3D12) : const Color(0xFF1C1C1F),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.fasting, style: TextStyle(color: running ? Colors.white : null, fontWeight: FontWeight.w700, fontSize: 22)),
                if (enabled && running) ...[
                  const SizedBox(height: 8),
                  Text(
                    _clock(left),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 52, fontFeatures: [FontFeature.tabularFigures()]),
                  ),
                  Text(
                    '${t.approximateEnd}: ${endsAt == null ? '' : _jerusalemTime(endsAt)}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFFF3F0EC)),
                  ),
                ],
                if (enabled && !running)
                  Text(
                    '${t.scheduled}: ${fasting!['startHour'].toString().padLeft(2, '0')}:00 – ${fasting!['endHour'].toString().padLeft(2, '0')}:00 · ${fasting!['lengthHours']} ${t.hours}',
                  ),
                const SizedBox(height: 12),
                if (enabled)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(64),
                      backgroundColor: running ? const Color(0xFFF3F0EC) : null,
                      foregroundColor: running ? const Color(0xFF3A2418) : null,
                      textStyle: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                    ),
                    onPressed: () async {
                      try {
                        await widget.api.send('POST', running ? '/api/fasting/stop' : '/api/fasting/start');
                        await load();
                      } on ApiException catch (err) {
                        setState(() => error = t.error(err.code));
                      }
                    },
                    child: Text(running ? t.stopFast : t.startFast),
                  )
                else if (fasting != null)
                  Text(t.error('fasting_disabled')),
                if (error.isNotEmpty) Text(error, style: const TextStyle(color: Color(0xFFFFB4A8))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.fastLog, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (sessions.isEmpty)
                  Text(t.noFasts)
                else
                  Table(
                    columnWidths: const {
                      0: FlexColumnWidth(1.4),
                      1: FlexColumnWidth(1.1),
                      2: FlexColumnWidth(0.9),
                      3: FlexColumnWidth(1.3),
                    },
                    children: [
                      TableRow(children: [
                        _cell(t.date, header: true),
                        _cell(t.length, header: true),
                        _cell(t.start, header: true),
                        _cell(t.end, header: true),
                      ]),
                      for (final session in sessions)
                        TableRow(children: [
                          _cell(_jerusalemDate(session['startedAt'] as String)),
                          _cell(_fastLength(session)),
                          _cell(_jerusalemTime(session['startedAt'] as String)),
                          _cell(_fastEnd(session, t.approx)),
                        ]),
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
    child: Text(text, style: TextStyle(fontWeight: header ? FontWeight.w700 : null, fontSize: header ? 13 : 14, fontFeatures: const [FontFeature.tabularFigures()])),
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
    final days = (week!['days'] as List).cast<Map>();
    return FadeIn(
      key: ValueKey(week!['sunday']),
      child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          TextButton(onPressed: () { on = _shift(week!['sunday'] as String, -7); load(); }, child: Text(t.previousWeek)),
          TextButton(onPressed: () { on = _shift(week!['sunday'] as String, 7); load(); }, child: Text(t.nextWeek)),
        ]),
        Text('${t.calorieIntake}: ${week!['calorieIntake']}'),
        Text('${t.successCount}: ${week!['successCount']}'),
        Text('${t.weightChange}: ${week!['weightChangeKg'] ?? t.noWeightChange}'),
        for (final day in days)
          ListTile(
            title: Text(day['day'] as String),
            subtitle: Text('${day['calories']} / ${day['goalKcal']}'),
            trailing: Text(day['future'] == true || (day['success'] != true && day['calories'] == 0)
                ? t.notYet
                : day['success'] == true
                    ? t.success
                    : t.missed),
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
    setState(() => weights = (data['weights'] as List).cast<Map<String, dynamic>>());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(controller: controller, decoration: InputDecoration(labelText: t.weightKg), keyboardType: TextInputType.number),
        FilledButton(
          onPressed: () async {
            await widget.api.send('POST', '/api/weights', body: {'weightKg': num.parse(controller.text)});
            controller.clear();
            await load();
          },
          child: Text(t.logWeight),
        ),
        const SizedBox(height: 12),
        if (weights.isEmpty) Text(t.graphEmpty) else SizedBox(height: 180, child: AnimatedWeightChart(weights: weights)),
        for (final point in weights.reversed) ListTile(title: Text('${point['weightKg']} kg'), subtitle: Text(point['loggedAt'] as String)),
      ],
    );
  }
}

class WeightPainter extends CustomPainter {
  WeightPainter(this.weights, this.progress);
  final List<Map<String, dynamic>> weights;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final dot = Paint()..color = const Color(0xFFE07A2F).withValues(alpha: progress.clamp(0, 1));
    if (weights.length < 2) {
      if (weights.isNotEmpty) {
        canvas.drawCircle(Offset(size.width / 2, size.height / 2), 4, dot);
      }
      return;
    }
    final times = weights.map((point) => DateTime.parse(point['loggedAt'] as String).millisecondsSinceEpoch.toDouble()).toList();
    final values = weights.map((point) => (point['weightKg'] as num).toDouble()).toList();
    final minT = times.reduce((a, b) => a < b ? a : b);
    final maxT = times.reduce((a, b) => a > b ? a : b);
    final minV = values.reduce((a, b) => a < b ? a : b);
    final maxV = values.reduce((a, b) => a > b ? a : b);
    final paint = Paint()
      ..color = const Color(0xFFE07A2F)
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    final spots = <Offset>[];
    for (var i = 0; i < weights.length; i++) {
      final x = maxT == minT ? size.width / 2 : (times[i] - minT) / (maxT - minT) * (size.width - 16) + 8;
      final y = maxV == minV ? size.height / 2 : size.height - 8 - (values[i] - minV) / (maxV - minV) * (size.height - 16);
      final spot = Offset(x, y);
      spots.add(spot);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    final metric = path.computeMetrics().first;
    canvas.drawPath(metric.extractPath(0, metric.length * progress.clamp(0, 1)), paint);
    for (var i = 0; i < spots.length; i++) {
      final along = i / (spots.length - 1);
      if (along > progress) continue;
      canvas.drawCircle(spots[i], 4, Paint()..color = const Color(0xFFE07A2F));
    }
  }

  @override
  bool shouldRepaint(covariant WeightPainter oldDelegate) => oldDelegate.progress != progress || oldDelegate.weights != weights;
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.api, required this.t, required this.me, required this.onMe, required this.sync});
  final Api api;
  final Copy t;
  final Map<String, dynamic> me;
  final ValueChanged<Map<String, dynamic>> onMe;
  final Future<void> Function() sync;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Map<String, dynamic>? profile;
  Map<String, dynamic>? fasting;
  bool autoPublish = false;
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmPassword = TextEditingController();
  String passwordError = '';
  String passwordStatus = '';

  bool get _ruleLength => newPassword.text.length >= 8 && newPassword.text.length <= 200;
  bool get _ruleEnglish => newPassword.text.isNotEmpty && RegExp(r'^[\x21-\x7E]+$').hasMatch(newPassword.text);
  bool get _ruleUppercase => RegExp(r'[A-Z]').hasMatch(newPassword.text);
  bool get _ruleNumber => RegExp(r'[0-9]').hasMatch(newPassword.text);
  bool get _ruleSymbol => RegExp(r'[\x21-\x2F\x3A-\x40\x5B-\x60\x7B-\x7E]').hasMatch(newPassword.text);
  bool get _ruleMatch => newPassword.text.isNotEmpty && newPassword.text == confirmPassword.text;
  bool get _passwordValid =>
      currentPassword.text.isNotEmpty && _ruleLength && _ruleEnglish && _ruleUppercase && _ruleNumber && _ruleSymbol && _ruleMatch;

  @override
  void initState() {
    super.initState();
    autoPublish = widget.me['user']['autoPublishFoods'] == true;
    unawaited(load());
  }

  @override
  void dispose() {
    currentPassword.dispose();
    newPassword.dispose();
    confirmPassword.dispose();
    super.dispose();
  }

  Widget _ruleRow(bool ok, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        '${ok ? '✓' : '○'} $label',
        style: TextStyle(color: ok ? const Color(0xFF8FD9A8) : const Color(0xFFB7B1AA), fontSize: 13),
      ),
    );
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        DropdownButtonFormField<String>(
          initialValue: widget.me['user']['language'] as String,
          decoration: InputDecoration(labelText: t.language),
          items: [DropdownMenuItem(value: 'en', child: Text(t.english)), DropdownMenuItem(value: 'he', child: Text(t.hebrew))],
          onChanged: (value) async {
            if (value == null) return;
            await widget.api.send('PUT', '/api/profile/settings', body: {'language': value, 'autoPublishFoods': autoPublish});
            widget.onMe(await widget.api.send('GET', '/api/auth/me'));
          },
        ),
        SwitchListTile(
          title: Text(t.autoPublish),
          value: autoPublish,
          onChanged: (value) async {
            setState(() => autoPublish = value);
            await widget.api.send('PUT', '/api/profile/settings', body: {
              'language': widget.me['user']['language'],
              'autoPublishFoods': value,
            });
          },
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(t.changePassword, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                TextField(
                  controller: currentPassword,
                  decoration: InputDecoration(labelText: t.currentPassword),
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: newPassword,
                  decoration: InputDecoration(labelText: t.newPassword),
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmPassword,
                  decoration: InputDecoration(labelText: t.confirmPassword),
                  obscureText: true,
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 10),
                Text(t.passwordRulesTitle, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                _ruleRow(_ruleLength, t.ruleLength),
                _ruleRow(_ruleEnglish, t.ruleEnglish),
                _ruleRow(_ruleUppercase, t.ruleUppercase),
                _ruleRow(_ruleNumber, t.ruleNumber),
                _ruleRow(_ruleSymbol, t.ruleSymbol),
                _ruleRow(_ruleMatch, t.ruleMatch),
                if (passwordError.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(passwordError, style: const TextStyle(color: Colors.red)),
                ],
                if (passwordStatus.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(passwordStatus, style: const TextStyle(color: Color(0xFF8FD9A8))),
                ],
                const SizedBox(height: 10),
                FilledButton(
                  onPressed: !_passwordValid
                      ? null
                      : () async {
                          try {
                            await widget.api.send('PUT', '/api/auth/password', body: {
                              'currentPassword': currentPassword.text,
                              'newPassword': newPassword.text,
                              'confirmPassword': confirmPassword.text,
                            });
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
        if (profile != null) Text('${t.weightKg}: ${profile!['weightKg']} · ${t.goal}'),
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
      final res = await widget.api.send('PUT', '/api/rbac/permissions', body: {
        'permissions': {op: allowed},
      });
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(t.permissions, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 4),
        Text(t.permissionsDesc, style: const TextStyle(color: Color(0xFFB7B1AA))),
        const SizedBox(height: 12),
        if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
        Card(
          child: Column(
            children: [
              for (final op in operations)
                SwitchListTile(
                  title: Text(t.operationLabel(op)),
                  subtitle: Text(op, style: const TextStyle(color: Color(0xFFB7B1AA), fontSize: 12)),
                  value: permissions[op] ?? false,
                  onChanged: (value) => toggle(op, value),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class FoodActions extends StatefulWidget {
  const FoodActions({super.key, required this.api, required this.t, required this.food, required this.admin});
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
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(food['name'] as String, style: Theme.of(context).textTheme.titleLarge),
          if (food['verified'] == true) Text(t.verified),
          if (food['owned'] == true)
            OutlinedButton(
              onPressed: () async {
                final path = food['published'] == true ? 'unpublish' : 'publish';
                final result = await widget.api.send('POST', '/api/foods/${food['id']}/$path');
                setState(() => food = (result['food'] as Map).cast<String, dynamic>());
              },
              child: Text(food['published'] == true ? t.unpublish : t.publish),
            ),
          if (widget.admin && food['published'] == true && food['verified'] != true)
            OutlinedButton(
              onPressed: () async {
                final result = await widget.api.send('POST', '/api/foods/${food['id']}/verify');
                setState(() => food = (result['food'] as Map).cast<String, dynamic>());
              },
              child: Text(t.verify),
            ),
          FilledButton(onPressed: () => Navigator.pop(context, food), child: Text(t.add)),
        ],
      ),
    );
  }
}

class FastingEditor extends StatefulWidget {
  const FastingEditor({super.key, required this.t, required this.fasting, required this.onSave});
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
    return Column(
      children: [
        SwitchListTile(title: Text(t.fasting), value: enabled, onChanged: (value) => setState(() => enabled = value)),
        DropdownButtonFormField<int>(
          initialValue: length,
          decoration: InputDecoration(labelText: t.fastingLength),
          items: [12, 14, 16].map((value) => DropdownMenuItem(value: value, child: Text('$value ${t.hours}'))).toList(),
          onChanged: (value) => setState(() => length = value ?? length),
        ),
        hourPicker(t.startHour, startHour, (value) => setState(() => startHour = value)),
        Text('${t.endHour}: ${((startHour + length) % 24).toString().padLeft(2, '0')}:00'),
        FilledButton(
          onPressed: () => widget.onSave({
            'enabled': enabled,
            'lengthHours': length,
            'startHour': startHour,
          }),
          child: Text(t.save),
        ),
      ],
    );
  }
}

class FoodScreen extends StatefulWidget {
  const FoodScreen({super.key, required this.api, required this.t, required this.barcode});
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
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('${t.barcode}: ${widget.barcode}'),
          TextField(controller: name, decoration: InputDecoration(labelText: t.name)),
          DropdownButtonFormField<String>(
            initialValue: basis,
            items: [DropdownMenuItem(value: 'solid', child: Text(t.solid)), DropdownMenuItem(value: 'liquid', child: Text(t.liquid))],
            onChanged: (value) => setState(() => basis = value ?? 'solid'),
          ),
          TextField(controller: calories, decoration: InputDecoration(labelText: t.calories), keyboardType: TextInputType.number),
          TextField(controller: protein, decoration: InputDecoration(labelText: t.protein), keyboardType: TextInputType.number),
          TextField(controller: carbohydrates, decoration: InputDecoration(labelText: t.carbohydrates), keyboardType: TextInputType.number),
          TextField(controller: fat, decoration: InputDecoration(labelText: t.fat), keyboardType: TextInputType.number),
          TextField(controller: fiber, decoration: InputDecoration(labelText: t.fiber), keyboardType: TextInputType.number),
          TextField(controller: sugars, decoration: InputDecoration(labelText: t.sugars), keyboardType: TextInputType.number),
          TextField(controller: sodium, decoration: InputDecoration(labelText: t.sodium), keyboardType: TextInputType.number),
          if (error.isNotEmpty) Text(error, style: const TextStyle(color: Colors.red)),
          FilledButton(
            onPressed: () async {
              try {
                final created = await widget.api.send('POST', '/api/foods', body: {
                  'barcode': widget.barcode,
                  'name': name.text.trim(),
                  'basis': basis,
                  'calories': num.parse(calories.text),
                  'protein': num.parse(protein.text),
                  'carbohydrates': num.parse(carbohydrates.text),
                  'fat': num.parse(fat.text),
                  'fiber': num.parse(fiber.text),
                  'sugars': num.parse(sugars.text),
                  'sodium': num.parse(sodium.text),
                });
                if (context.mounted) Navigator.pop(context, (created['food'] as Map).cast<String, dynamic>());
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
  return DropdownButtonFormField<int>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [for (var hour = 0; hour < 24; hour++) DropdownMenuItem(value: hour, child: Text('${hour.toString().padLeft(2, '0')}:00'))],
    onChanged: (next) => onChanged(next ?? value),
  );
}

Future<String?> askText(BuildContext context, String label) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(label),
      content: TextField(controller: controller, autofocus: true, keyboardType: TextInputType.number),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('OK')),
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
  final sameDay = started.year == ended.year && started.month == ended.month && started.day == ended.day;
  final label = sameDay ? time : '$time · ${_padDate(ended)}';
  return running ? '$label $approximate' : label;
}

tz.TZDateTime _jerusalem(String iso) {
  return tz.TZDateTime.from(DateTime.parse(iso), tz.getLocation('Asia/Jerusalem'));
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

class SoftPageTransitionsBuilder extends PageTransitionsBuilder {
  const SoftPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
  }
}

class SoftSwitcher extends StatelessWidget {
  const SoftSwitcher({super.key, required this.child, this.duration = const Duration(milliseconds: 320)});
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
        children: [
          ...previous,
          ?current,
        ],
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
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
  late final CurvedAnimation opacity = CurvedAnimation(parent: controller, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
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
  const EaseBuilder({super.key, required this.value, required this.builder, this.from, this.duration = const Duration(milliseconds: 700)});
  final double value;
  final double? from;
  final Duration duration;
  final Widget Function(BuildContext context, double value) builder;

  @override
  State<EaseBuilder> createState() => _EaseBuilderState();
}

class _EaseBuilderState extends State<EaseBuilder> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: widget.duration);
  late double _from;
  late double _to;

  bool get _reduce => WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

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
    return AnimatedBuilder(animation: _controller, builder: (context, _) => widget.builder(context, _shown));
  }
}

class AnimatedWeightChart extends StatefulWidget {
  const AnimatedWeightChart({super.key, required this.weights});
  final List<Map<String, dynamic>> weights;

  @override
  State<AnimatedWeightChart> createState() => _AnimatedWeightChartState();
}

class _AnimatedWeightChartState extends State<AnimatedWeightChart> with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));

  @override
  void initState() {
    super.initState();
    if (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
      controller.value = 1;
    } else {
      controller.forward();
    }
  }

  @override
  void didUpdateWidget(AnimatedWeightChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.weights.length != widget.weights.length && !WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations) {
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
        painter: WeightPainter(widget.weights, Curves.easeOutCubic.transform(controller.value)),
        child: const SizedBox.expand(),
      ),
    );
  }
}
