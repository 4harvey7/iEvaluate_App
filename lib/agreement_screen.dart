import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'login_screen.dart';

class AgreementScreen extends StatefulWidget {
  const AgreementScreen({super.key});

  @override
  State<AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends State<AgreementScreen> {
  // State variables for the checkboxes
  bool _isNdaChecked = false;
  bool _isDpaChecked = false;

  @override
  Widget build(BuildContext context) {
    // The button is only active if BOTH are true
    bool canLogin = _isNdaChecked && _isDpaChecked;

    return Scaffold(
      backgroundColor: AppColors.white,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ==========================================
            // HEADER SECTION
            // ==========================================
            Container(
              padding: const EdgeInsets.only(
                  left: 24.0, right: 24.0, top: 20.0, bottom: 16.0),
              color: AppColors.deepBlue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Text(
                        'iEvaluate',
                        style: TextStyle(
                          color: AppColors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ],
                  ),
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: AppColors.white,
                    backgroundImage: AssetImage('assets/images/CTU_logo.png'),
                  ),
                ],
              ),
            ),

            // ==========================================
            // SCROLLABLE CONTENT SECTION
            // ==========================================
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                    left: 24.0, right: 24.0, bottom: 24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    const Text(
                      'Welcome to iEvaluate. Please review and\naccept our data usage policies before you\nlogin.',
                      style: TextStyle(
                        color: AppColors.darkGray,
                        fontSize: 15,
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // NDA Card
                    _buildAgreementCard(
                      title: 'Non-Disclosure Agreement (NDA)',
                      richBody: const TextSpan(
                        style: TextStyle(
                            color: AppColors.darkGray,
                            fontSize: 13.5,
                            height: 1.5),
                        children: [
                          TextSpan(
                            text: 'By proceeding',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          TextSpan(
                            text:
                            ', you agree to treat all system data—evaluations, instructor ratings, performance analyses—with strict confidentiality. You will not disclose this data to unauthorized parties.',
                          ),
                        ],
                      ),
                      badgeText: 'Read Full NDA',
                    ),
                    const SizedBox(height: 20),

                    // DPA Card
                    _buildAgreementCard(
                      title: 'Data Privacy Agreement (DPA)',
                      richBody: const TextSpan(
                        style: TextStyle(
                            color: AppColors.darkGray,
                            fontSize: 13.5,
                            height: 1.5),
                        children: [
                          TextSpan(
                            text:
                            'We process personal data and evaluation inputs in full compliance with the Data Privacy Act. By proceeding, you consent to this processing for academic evaluation purposes.',
                          ),
                        ],
                      ),
                      badgeText: 'Read Privacy Policy',
                    ),

                    const SizedBox(height: 32),

                    // ==========================================
                    // CHECKBOX & ACTION AREA
                    // ==========================================

                    // Checkbox 1: NDA
                    Row(
                      children: [
                        Checkbox(
                          value: _isNdaChecked,
                          onChanged: (value) {
                            setState(() {
                              _isNdaChecked = value ?? false;
                            });
                          },
                          activeColor: AppColors.deepBlue,
                          checkColor: AppColors.white,
                        ),
                        const Expanded(
                          child: Text(
                            "I have read and agree to the Non-Disclosure Agreement",
                            style: TextStyle(
                              color: AppColors.darkGray,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    // Checkbox 2: DPA
                    Row(
                      children: [
                        Checkbox(
                          value: _isDpaChecked,
                          onChanged: (value) {
                            setState(() {
                              _isDpaChecked = value ?? false;
                            });
                          },
                          activeColor: AppColors.deepBlue,
                          checkColor: AppColors.white,
                        ),
                        const Expanded(
                          child: Text(
                            "I have read and agree to the Data Privacy Agreement",
                            style: TextStyle(
                              color: AppColors.darkGray,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 24),

                    // Bottom Action Button
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: canLogin
                            ? () {
                          // <-- CHANGED: Now navigates to the LoginScreen!
                          Navigator.pushReplacement(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                          );
                        }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                          canLogin ? AppColors.gold : Colors.grey.shade300,
                          foregroundColor: canLogin
                              ? AppColors.deepBlue
                              : Colors.grey.shade500,
                          elevation: canLogin ? 4 : 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(25),
                          ),
                        ),
                        child: const Text(
                          'Accept and Proceed to Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
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
    );
  }

  // Simplified Agreement Card
  Widget _buildAgreementCard({
    required String title,
    required TextSpan richBody,
    required String badgeText,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.lightGray,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.darkGray,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          RichText(text: richBody),
          const SizedBox(height: 16),
          InkWell(
            onTap: () {},
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.royalBlue,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    badgeText,
                    style: const TextStyle(
                      color: AppColors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.white,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}