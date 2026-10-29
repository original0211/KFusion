part of '../action.dart';

@Riverpod(keepAlive: true)
class IconSetsAction extends _$IconSetsAction {
  @override
  void build() {}

  Future<IconSet> sync(IconSet iconSet) async {
    final before = await _stored(iconSet.id);
    final content = await _download(iconSet.url);
    final latest = before == null ? null : await _stored(iconSet.id);
    if (before != null && (latest == null || latest.url != before.url)) {
      return latest ?? iconSet;
    }
    final base = switch ((before, latest)) {
      (final before?, final latest?) => latest.copyWith(
        name: iconSet.name == before.name ? latest.name : iconSet.name,
        url: iconSet.url,
      ),
      _ => iconSet,
    };
    return _put(
      base.copyWith(icons: content.icons, lastUpdateTime: DateTime.now()),
    );
  }

  Future<IconSet?> _stored(int id) async {
    final rows =
        ref.read(iconSetsProvider).value ??
        await database.iconSetsDao.query().get();
    return rows.where((item) => item.id == id).firstOrNull;
  }

  IconSet _put(IconSet iconSet) {
    ref.read(iconSetsProvider.notifier).put(iconSet);
    return iconSet;
  }

  Future<({String name, List<IconSetIcon> icons})> _download(String url) async {
    final response = await request.getTextResponseForUrl(url);
    return _parse(response.data ?? '');
  }

  ({String name, List<IconSetIcon> icons}) _parse(String content) {
    try {
      return parseIconSet(content);
    } on FormatException {
      throw MessageException(currentAppLocalizations.invalidIconSet);
    }
  }
}
