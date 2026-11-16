import 'dart:ui' as ui;

import 'landing_page.dart';

import 'package:flutter/material.dart';

import 'login.dart';

class LandingPage extends StatelessWidget {
  const LandingPage({super.key});

  static const Color academicBlue = Color(0xFF245A91);
  static const Color darkBlue = Color(0xFF102F4D);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        child: Column(
          children: [
            // HERO SECTION
            SizedBox(
              height: 600,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                    child: Image.asset(
                      'assets/aces_building.png',
                      fit: BoxFit.cover,
                    ),
                  ),

                  Container(color: darkBlue.withValues(alpha: 0.72)),

                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 30,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Image.asset(
                            'assets/aces_logo.png',
                            height: 125,
                            width: 125,
                            fit: BoxFit.contain,
                          ),

                          const SizedBox(height: 22),

                          const Text(
                            'ACES TAGUM COLLEGE',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),

                          const SizedBox(height: 10),

                          const Text(
                            'ABOUT THE CAMPUS',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 4,
                            ),
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            'Welcome to ACES Tagum College',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),

                          const SizedBox(height: 12),

                          const Text(
                            'Discover our campus, explore learning opportunities, '
                            'and stay connected with the ACES community.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.6,
                            ),
                          ),

                          const SizedBox(height: 32),

                          SizedBox(
                            width: 210,
                            height: 52,
                            child: ElevatedButton(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LoginPage(),
                                  ),
                                );
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: academicBlue,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'LOGIN',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ABOUT SECTION
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 55),
              child: Column(
                children: [
                  const Text(
                    'About Our Campus',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: darkBlue,
                      fontSize: 27,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 16),

                  const Text(
                    'ACES Tagum College is a learning community dedicated '
                    'to providing students with opportunities to grow, '
                    'develop their skills, and prepare for their future.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey,
                      fontSize: 15,
                      height: 1.8,
                    ),
                  ),

                  const SizedBox(height: 40),

                  const Text(
                    'Explore Our Campus',
                    style: TextStyle(
                      color: darkBlue,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 25),

                  _campusFeature(
                    icon: Icons.school_outlined,
                    title: 'Learning Environment',
                    description:
                        'A campus environment that supports learning, '
                        'growth, and student development.',
                  ),

                  _campusFeature(
                    icon: Icons.groups_outlined,
                    title: 'Student Community',
                    description:
                        'Stay connected through campus clubs, activities, '
                        'and student participation.',
                  ),

                  _campusFeature(
                    icon: Icons.event_available_outlined,
                    title: 'Campus Activities',
                    description:
                        'Keep updated with school events, announcements, '
                        'and important campus schedules.',
                  ),

                  const SizedBox(height: 30),

                  SizedBox(
                    width: 220,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: academicBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'ACCESS CAMPUS PORTAL',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // FOOTER
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(25),
              color: darkBlue,
              child: const Column(
                children: [
                  Text(
                    'ACES TAGUM COLLEGE',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Your Campus. Your Community. Your Future.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _campusFeature({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F6FA),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: academicBlue, size: 34),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: darkBlue,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 14,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
