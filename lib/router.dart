import 'package:go_router/go_router.dart';

import 'screens/dashboard_screen.dart';
import 'screens/file_transfer_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/welcome_tour_screen.dart';
import 'widgets/app_shell.dart';

final router = GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) {
        return AppShell(currentRoute: state.uri.path, child: child);
      },
      routes: [
        GoRoute(
          path: '/',
          name: 'dashboard',
          builder: (context, state) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/files',
          name: 'files',
          builder: (context, state) => const FileTransferScreen(),
        ),
        GoRoute(
          path: '/settings',
          name: 'settings',
          builder: (context, state) => const SettingsScreen(),
        ),
      ],
    ),
    GoRoute(
      path: '/welcome',
      name: 'welcome',
      builder: (context, state) => const WelcomeTourScreen(),
    ),
  ],
);
