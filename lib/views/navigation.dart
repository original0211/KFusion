import 'package:kfusion/common/app_ports.dart';
import 'package:kfusion/enum/enum.dart';
import 'package:kfusion/models/models.dart';
import 'package:kfusion/ui/icons/app_glyphs.dart';
import 'package:kfusion/views/dashboard/hara_dashboard.dart';
import 'package:kfusion/views/views.dart';
import 'package:material_ui/material_ui.dart';

class Navigation implements NavigationPort {
  static Navigation? _instance;

  // The shell carries exactly three entries (main screen, subscriptions,
  // settings). The record pages retired with the screen plan and logs /
  // resources moved behind the settings page's advanced gate, so nothing
  // else is listed here; openLogs and hasProxies stay only for the port
  // signature.
  @override
  List<NavigationItem> getItems({
    bool openLogs = false,
    bool hasProxies = false,
  }) {
    return [
      NavigationItem(
        glyph: AppGlyphs.dashboard,
        label: PageLabel.dashboard,
        builder: (_) =>
            const HaraDashboard(key: GlobalObjectKey(PageLabel.dashboard)),
      ),
      NavigationItem(
        glyph: AppGlyphs.profiles,
        label: PageLabel.profiles,
        builder: (_) =>
            const ProfilesView(key: GlobalObjectKey(PageLabel.profiles)),
      ),
      NavigationItem(
        glyph: AppGlyphs.tools,
        label: PageLabel.tools,
        builder: (_) => const ToolsView(key: GlobalObjectKey(PageLabel.tools)),
        modes: [NavigationItemMode.desktop, NavigationItemMode.mobile],
      ),
    ];
  }

  Navigation._internal();

  factory Navigation() {
    _instance ??= Navigation._internal();
    return _instance!;
  }
}

final navigation = Navigation();
