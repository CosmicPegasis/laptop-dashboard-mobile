import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AppShell extends StatelessWidget {
  final String currentRoute;
  final Widget child;

  const AppShell({super.key, required this.currentRoute, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_getTitle()),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      drawer: _buildDrawer(context),
      body: child,
    );
  }

  String _getTitle() {
    switch (currentRoute) {
      case '/files':
        return 'File Transfer';
      case '/settings':
        return 'Settings';
      default:
        return 'Laptop Dashboard';
    }
  }

  Widget _buildDrawer(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
            ),
            child: const Align(
              alignment: Alignment.bottomLeft,
              child: Text(
                'Laptop Dashboard',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          _drawerTile(context, '/', Icons.dashboard, 'Dashboard', currentRoute),
          _drawerTile(
            context,
            '/files',
            Icons.upload_file,
            'File Transfer',
            currentRoute,
          ),
          _drawerTile(
            context,
            '/settings',
            Icons.settings,
            'Settings',
            currentRoute,
          ),
        ],
      ),
    );
  }

  Widget _drawerTile(
    BuildContext context,
    String route,
    IconData icon,
    String title,
    String currentRoute,
  ) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      selected: currentRoute == route,
      onTap: () {
        context.go(route);
        Navigator.pop(context);
      },
    );
  }
}
