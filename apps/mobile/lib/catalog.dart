import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'api.dart';
import 'copy.dart';
import 'theme.dart';

String _plain(num value) =>
    value == value.roundToDouble() ? value.round().toString() : value.toString();

/// Every published food, or your own. Admins (foods:verify) can verify entries.
class CatalogScreen extends StatefulWidget {
  const CatalogScreen({
    super.key,
    required this.api,
    required this.t,
    required this.canVerify,
    required this.onCreateFood,
    required this.onEditFood,
  });

  final Api api;
  final Copy t;
  final bool canVerify;

  /// Opens the "new food" form; resolves to the created food, or null.
  final Future<Map<String, dynamic>?> Function() onCreateFood;

  /// Opens the form for one of the user's foods; resolves to the saved food, or null.
  final Future<Map<String, dynamic>?> Function(Map<String, dynamic> food) onEditFood;

  @override
  State<CatalogScreen> createState() => _CatalogScreenState();
}

class _CatalogScreenState extends State<CatalogScreen> {
  String scope = 'published';
  String status = 'all';
  final search = TextEditingController();
  Timer? debounce;
  List<Map<String, dynamic>>? foods;
  bool hasMore = false;
  bool loadingMore = false;
  String error = '';
  int request = 0;

  Copy get t => widget.t;

  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    debounce?.cancel();
    search.dispose();
    super.dispose();
  }

  String path(int offset) {
    final query = Uri(
      queryParameters: {
        'scope': scope,
        'status': status,
        'offset': '$offset',
        if (search.text.trim().isNotEmpty) 'q': search.text.trim(),
      },
    ).query;
    return '/api/foods/catalog?$query';
  }

  Future<void> load() async {
    final id = ++request;
    setState(() => error = '');
    try {
      final res = await widget.api.send('GET', path(0));
      if (!mounted || id != request) return; // a newer filter already answered
      setState(() {
        foods = (res['foods'] as List).cast<Map>().map((f) => f.cast<String, dynamic>()).toList();
        hasMore = res['hasMore'] == true;
      });
    } on ApiException catch (err) {
      if (mounted && id == request) setState(() => error = t.error(err.code));
    }
  }

  Future<void> loadMore() async {
    final current = foods;
    if (current == null || loadingMore) return;
    final id = request;
    setState(() => loadingMore = true);
    try {
      final res = await widget.api.send('GET', path(current.length));
      if (!mounted || id != request) return;
      setState(() {
        foods = [
          ...current,
          ...(res['foods'] as List).cast<Map>().map((f) => f.cast<String, dynamic>()),
        ];
        hasMore = res['hasMore'] == true;
      });
    } on ApiException catch (err) {
      if (mounted) setState(() => error = t.error(err.code));
    } finally {
      if (mounted) setState(() => loadingMore = false);
    }
  }

  void onSearchChanged(String _) {
    debounce?.cancel();
    debounce = Timer(const Duration(milliseconds: 250), load);
  }

  /// Only one verified food per barcode: the server un-verifies the others.
  void applyVerified(Map<String, dynamic> verified) {
    setState(() {
      foods = [
        for (final food in foods ?? <Map<String, dynamic>>[])
          if (food['id'] == verified['id'])
            verified
          else if (verified['barcode'] != null && food['barcode'] == verified['barcode'])
            {...food, 'verified': false}
          else
            food,
      ];
    });
  }

  void replaceFood(Map<String, dynamic> updated) {
    setState(() {
      foods = [
        for (final food in foods ?? <Map<String, dynamic>>[])
          food['id'] == updated['id'] ? updated : food,
      ];
    });
  }

  Future<void> showDetail(Map<String, dynamic> food) async {
    final result = await showModalBottomSheet<_DetailResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FoodDetail(
        api: widget.api,
        t: t,
        food: food,
        canVerify: widget.canVerify,
        onChanged: replaceFood,
      ),
    );
    if (result == null || !mounted) return;
    switch (result.action) {
      case _DetailAction.verified:
        applyVerified(result.food);
      case _DetailAction.deleted:
        setState(() {
          foods = [
            for (final item in foods ?? <Map<String, dynamic>>[])
              if (item['id'] != result.food['id']) item,
          ];
        });
      case _DetailAction.edit:
        final saved = await widget.onEditFood(result.food);
        if (saved != null && mounted) replaceFood(saved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final apple = context.apple;
    final list = foods;
    return ListView(
      padding: const EdgeInsets.all(Gaps.lg),
      children: [
        AppleSegmented<String>(
          value: scope,
          options: [
            AppleMenuOption('published', t.catalogPublished),
            AppleMenuOption('mine', t.catalogMine),
          ],
          onChanged: (value) {
            setState(() => scope = value);
            load();
          },
        ),
        const SizedBox(height: Gaps.md),
        TextField(
          controller: search,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: t.catalogSearch,
            prefixIcon: const Icon(Icons.search),
          ),
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: Gaps.md),
        AppleSegmented<String>(
          value: status,
          options: [
            AppleMenuOption('all', t.catalogAll),
            AppleMenuOption('verified', t.verified),
            AppleMenuOption('unverified', t.catalogUnverified),
          ],
          onChanged: (value) {
            setState(() => status = value);
            load();
          },
        ),
        if (scope == 'mine') ...[
          const SizedBox(height: Gaps.md),
          SizedBox(
            height: Gaps.hit,
            child: FilledButton(
              onPressed: () async {
                final created = await widget.onCreateFood();
                if (created != null) load();
              },
              child: Text(t.createFood),
            ),
          ),
        ],
        const SizedBox(height: Gaps.md),
        if (error.isNotEmpty) ErrorText(error),
        if (list == null && error.isEmpty)
          const Padding(
            padding: EdgeInsets.all(Gaps.xl),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (list != null && list.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: Text(
              scope == 'mine' && search.text.trim().isEmpty && status == 'all'
                  ? t.catalogEmptyMine
                  : t.catalogEmpty,
              style: TextStyle(color: apple.labelSecondary),
            ),
          ),
        if (list != null && list.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: apple.cardBg,
              borderRadius: BorderRadius.circular(Radii.card),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < list.length; i++) ...[
                  if (i > 0)
                    Divider(height: 0.5, thickness: 0.5, color: apple.separator),
                  _row(list[i], apple),
                ],
              ],
            ),
          ),
        if (hasMore)
          Padding(
            padding: const EdgeInsets.only(top: Gaps.md),
            child: SizedBox(
              height: Gaps.hit,
              child: OutlinedButton(
                onPressed: loadingMore ? null : loadMore,
                child: Text(t.catalogLoadMore),
              ),
            ),
          ),
      ],
    );
  }

  Widget _row(Map<String, dynamic> food, AppleColors apple) {
    final unit = food['basis'] == 'solid' ? t.grams : t.milliliters;
    final badges = [
      if (food['verified'] == true) t.verified,
      if (food['owned'] == true && food['published'] != true) t.catalogPrivate,
    ];
    return ListTile(
      minTileHeight: Gaps.hit,
      contentPadding: const EdgeInsets.symmetric(horizontal: Gaps.lg),
      title: Text(food['name'] as String, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${_plain((food['calories'] as num?) ?? 0)} ${t.kcal} / 100 $unit',
        style: TextStyle(color: apple.labelSecondary),
      ),
      trailing: badges.isEmpty
          ? null
          : Text(
              badges.join(' · '),
              style: TextStyle(
                color: food['verified'] == true
                    ? apple.accentPrimary
                    : apple.labelSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
      onTap: () => showDetail(food),
    );
  }
}

enum _DetailAction { verified, deleted, edit }

/// How the detail sheet closed, and the food it was showing at that moment.
class _DetailResult {
  const _DetailResult(this.action, this.food);
  final _DetailAction action;
  final Map<String, dynamic> food;
}

class _FoodDetail extends StatefulWidget {
  const _FoodDetail({
    required this.api,
    required this.t,
    required this.food,
    required this.canVerify,
    required this.onChanged,
  });
  final Api api;
  final Copy t;
  final Map<String, dynamic> food;
  final bool canVerify;

  /// The food changed while the sheet stays open (published or unpublished).
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  State<_FoodDetail> createState() => _FoodDetailState();
}

class _FoodDetailState extends State<_FoodDetail> {
  late Map<String, dynamic> food = widget.food;
  String error = '';
  bool busy = false;

  /// Runs one request with the buttons disabled; shows the error if it fails.
  Future<Map<String, dynamic>?> run(String method, String path) async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      return await widget.api.send(method, path);
    } on ApiException catch (err) {
      if (mounted) setState(() => error = widget.t.error(err.code));
      return null;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> togglePublished() async {
    final action = food['published'] == true ? 'unpublish' : 'publish';
    final res = await run('POST', '/api/foods/${food['id']}/$action');
    if (res == null || !mounted) return;
    final updated = (res['food'] as Map).cast<String, dynamic>();
    setState(() => food = updated);
    widget.onChanged(updated);
  }

  /// Deleting cannot be undone, so it is confirmed first.
  Future<void> delete() async {
    final t = widget.t;
    final confirmed = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (sheet) => CupertinoActionSheet(
        title: Text(food['name'] as String),
        message: Text(t.deleteFoodConfirm),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(sheet, true),
            child: Text(t.deleteFood),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheet, false),
          child: Text(t.cancel),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;
    final res = await run('DELETE', '/api/foods/${food['id']}');
    if (res == null || !mounted) return;
    Navigator.pop(context, _DetailResult(_DetailAction.deleted, food));
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    final apple = context.apple;
    final unit = food['basis'] == 'solid' ? t.grams : t.milliliters;
    final rows = [
      (t.calories, food['calories']),
      (t.protein, food['protein']),
      (t.carbohydrates, food['carbohydrates']),
      (t.fat, food['fat']),
      (t.fiber, food['fiber']),
      (t.sugars, food['sugars']),
      (t.sodium, food['sodium']),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          spacing: Gaps.sm,
          children: [
            Text(
              food['name'] as String,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            Text(
              [
                '/ 100 $unit',
                if (food['verified'] == true) t.verified,
                if (food['barcode'] != null) '${t.barcode}: ${food['barcode']}',
              ].join(' · '),
              style: TextStyle(color: apple.labelSecondary),
            ),
            for (final (label, value) in rows)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label),
                  Text(
                    _plain((value as num?) ?? 0),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            if (error.isNotEmpty) ErrorText(error),
            if (widget.canVerify &&
                food['published'] == true &&
                food['verified'] != true)
              SizedBox(
                height: Gaps.hit,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final res = await run(
                            'POST',
                            '/api/foods/${food['id']}/verify',
                          );
                          if (res == null || !context.mounted) return;
                          Navigator.pop(
                            context,
                            _DetailResult(
                              _DetailAction.verified,
                              (res['food'] as Map).cast<String, dynamic>(),
                            ),
                          );
                        },
                  child: Text(t.verify),
                ),
              ),
            if (food['owned'] == true) ...[
              SizedBox(
                height: Gaps.hit,
                child: OutlinedButton(
                  onPressed: busy
                      ? null
                      : () => Navigator.pop(
                            context,
                            _DetailResult(_DetailAction.edit, food),
                          ),
                  child: Text(t.edit),
                ),
              ),
              SizedBox(
                height: Gaps.hit,
                child: OutlinedButton(
                  onPressed: busy ? null : togglePublished,
                  child: Text(food['published'] == true ? t.unpublish : t.publish),
                ),
              ),
              SizedBox(
                height: Gaps.hit,
                child: TextButton(
                  onPressed: busy ? null : delete,
                  style: TextButton.styleFrom(
                    foregroundColor: apple.accentDangerText,
                  ),
                  child: Text(t.deleteFood),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
