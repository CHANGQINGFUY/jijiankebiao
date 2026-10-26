import 'package:flutter/material.dart';

import '../../routing/app_routes.dart';
import '../add_course/add_course_tab.dart';
import '../home/home_tab.dart';
import '../settings/settings_tab.dart';

/// App 主容器：底部导航承载「课表 / 添加 / 设置」三个 Tab。
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  static const List<String> _titles = <String>['课表', '添加课程', '设置'];

  void _selectTab(int index) {
    if (index == _currentIndex) {
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() => _currentIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_currentIndex]),
        actions: _currentIndex == 0
            ? <Widget>[
                IconButton(
                  tooltip: '周视图',
                  onPressed: () =>
                      Navigator.of(context).pushNamed(AppRoutes.weekView),
                  icon: const Icon(Icons.calendar_view_week_outlined),
                ),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _currentIndex,
          children: <Widget>[
            const HomeTab(),
            AddCourseTab(onSaved: () => _selectTab(0)),
            const SettingsTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: _selectTab,
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(
            icon: Icon(Icons.calendar_month_outlined),
            activeIcon: Icon(Icons.calendar_month),
            label: '课表',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.add_circle_outline),
            activeIcon: Icon(Icons.add_circle),
            label: '添加',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings),
            label: '设置',
          ),
        ],
      ),
    );
  }
}
