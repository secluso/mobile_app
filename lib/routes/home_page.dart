import 'package:flutter/material.dart';
import 'camera/list_cameras.dart';
import 'app_drawer.dart';

class HomePage extends StatefulWidget {
  HomePage();

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Widget _currentPage = CamerasPage(key: camerasPageKey);

  void _navigateTo(Widget page) {
    setState(() {
      _currentPage = page;
    });
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: null,
      drawer: AppDrawer(onNavigate: _navigateTo),
      body: _currentPage,
    );
  }
}
