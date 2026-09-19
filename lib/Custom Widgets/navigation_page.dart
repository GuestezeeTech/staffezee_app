import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:guestezee_staffs_app/Screens/completed_task_page.dart';
import 'package:guestezee_staffs_app/Screens/delivered_task_page.dart';
import 'package:guestezee_staffs_app/Screens/home_screen.dart';
import 'package:guestezee_staffs_app/Screens/processing_task_screen.dart';
// import 'package:guestezee_staffs_app/Screens/scheduled_task_page.dart';

/// Riverpod provider to manage the bottom navigation index globally
final bottomNavIndexProvider = StateProvider<int>((ref) => 0);

class NavigationPage extends ConsumerStatefulWidget {
  const NavigationPage({super.key, this.initialIndex});

  final int? initialIndex;

  @override
  ConsumerState<NavigationPage> createState() => _NavigationPageState();
}

class _NavigationPageState extends ConsumerState<NavigationPage> {
  late PageController _pageController;
  DateTime? _lastBackPressTime;

  final List<String> image = [
    'assets/images/nav1.png',
    'assets/images/nav2.png',
    // 'assets/images/nav2.png', // Scheduled tab removed
    'assets/images/nav3.png',
    'assets/images/nav3.png',
  ];
  final List<String> clickedImage = [
    'assets/images/nav1c.png',
    'assets/images/nav2c.png',
    // 'assets/images/nav2c.png', // Scheduled tab removed
    'assets/images/nav3c.png',
    'assets/images/nav3c.png',
  ];

  final List<String> labels = [
    'Assigned',
    'Processing',
    // 'Scheduled',
    'Completed',
    'Delivered',
  ];

  @override
  void initState() {
    super.initState();
    final int startIndex =
        widget.initialIndex ?? ref.read(bottomNavIndexProvider);
    _pageController = PageController(initialPage: startIndex);
    // Defer provider mutation to after first frame to avoid modifying providers during build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(bottomNavIndexProvider.notifier).state = startIndex;
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void onTabTapped(int index) {
    ref.read(bottomNavIndexProvider.notifier).state = index;
  }

  Future<bool> _onWillPop() async {
    final currentIndex = ref.read(bottomNavIndexProvider);

    // If not on assigned page (index 0), navigate to assigned page
    if (currentIndex != 0) {
      ref.read(bottomNavIndexProvider.notifier).state = 0;
      return false; // Don't exit app
    }

    // If on assigned page, check for double back press
    final now = DateTime.now();
    if (_lastBackPressTime == null ||
        now.difference(_lastBackPressTime!) > Duration(seconds: 2)) {
      // First back press or too much time passed
      _lastBackPressTime = now;

      // Show snackbar
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Press back again to exit'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );

      return false; // Don't exit app
    }

    // Second back press within 2 seconds - exit app
    return true;
  }

  Widget buildNavItem(int index) {
    // Sizes available if needed for future responsiveness
    // double screenHeight = MediaQuery.of(context).size.height;
    // double screenWidth = MediaQuery.of(context).size.width;
    final currentIndex = ref.watch(bottomNavIndexProvider);
    bool isSelected = currentIndex == index;
    return Expanded(
      child: Container(
        color: Colors.white,
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onTabTapped(index),
            child: AnimatedContainer(
              duration: Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(vertical: 10),
              // color: Colors.white,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 25,
                    width: 25,
                    child: Image.asset(
                      isSelected ? clickedImage[index] : image[index],
                    ),
                  ),
                  SizedBox(
                    height: 5,
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 10,
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Color(0xff8F9899),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(bottomNavIndexProvider);
    // Listen to provider changes and sync PageController (must be in build)
    ref.listen<int>(bottomNavIndexProvider, (previous, next) {
      if (_pageController.hasClients && next != _pageController.page?.round()) {
        _pageController.jumpToPage(next);
      }
    });
    return PopScope(
      canPop: false,
      onPopInvoked: (bool didPop) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        body: PageView(
          controller: _pageController,
          physics: NeverScrollableScrollPhysics(),
          onPageChanged: (index) {
            ref.read(bottomNavIndexProvider.notifier).state = index;
          },
          children: [
            HomeScreen(),
            ProcessingTaskPage(),
            // ScheduledTaskPage(),
            CompletedTaskPage(),
            DeliveredTaskPage(),
          ],
        ),
        bottomNavigationBar: Row(
          children: List.generate(4, (index) => buildNavItem(index)),
        ),
      ),
    );
  }
}
