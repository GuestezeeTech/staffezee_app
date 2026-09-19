import 'package:flutter/material.dart';
import 'package:guestezee_staffs_app/Services/local_storage_service.dart';

class StaticContentPage extends StatelessWidget {
  final String title;
  final bool isPrivacyPolicy;
  final bool isAboutUs;

  const StaticContentPage({
    super.key,
    required this.title,
    this.isPrivacyPolicy = false,
    this.isAboutUs = false,
  });

  @override
  Widget build(BuildContext context) {
    double screenWidth = MediaQuery.of(context).size.width;

    return Scaffold(
      body: Column(
        children: [
          // Gradient App Bar
          ClipRRect(
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(25)),
            child: Container(
              color: Colors.white,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Stack(
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.18,
                        width: screenWidth,
                        child: Image.asset(
                          'assets/images/appbarpic.png',
                          width: screenWidth,
                          fit: BoxFit.fill,
                        ),
                      ),
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16.0, vertical: 20),
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Row(
                              children: [
                                IconButton(
                                  icon: const Icon(
                                      Icons.keyboard_arrow_left_outlined,
                                      size: 40,
                                      color: Colors.white),
                                  onPressed: () => Navigator.pop(context),
                                ),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    title,
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ), // Content
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPrivacyPolicy)
                    _buildPrivacyPolicyContent(context)
                  else if (isAboutUs)
                    _buildAboutUsContent(context)
                  else
                    _buildTermsAndConditionsContent(context),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutUsContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('About Us'),
        SizedBox(height: 12),
        _buildParagraph(
            'Guestvento Technology Pvt Ltd, operating under the brand name GUESTEZEE, is a technology-driven company committed to delivering innovative and reliable solutions to enhance user experiences across the hospitality and service sectors. We provide a seamless platform for individuals, businesses, and organizations to access and engage with our products and services through our website, mobile site, and mobile applications.'),
        _buildParagraph(
            'As a responsible data controller and processor, we take user privacy and data security seriously. We are dedicated to safeguarding your personal information and maintaining transparency in our data collection and processing practices. Our privacy policy outlines our commitment to protecting your data while offering you the best possible service.'),
        _buildParagraph(
            'At GUESTEZEE, we strive to create value by offering a diverse range of services that meet the needs of our users. Whether you are a customer seeking convenient service access or a business looking for strategic technological solutions, our goal is to provide excellence, reliability, and ease of use at every touchpoint.'),
        _buildParagraph(
            'For any inquiries or concerns, please feel free to contact us. We are here to assist and ensure that your experience with us is both secure and satisfactory.'),
      ],
    );
  }

  Widget _buildTermsAndConditionsContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Terms and Conditions'),
        SizedBox(height: 12),
        _buildParagraph(
            'The content on the website www.guestezee.com, which includes text, images, audio clips, video clips, downloads, software, products for purchase, and other materials, are provided by Guestvento Technology Private Limited.) technology division for application and online transaction purposes only. By accessing the www.guestezee.com site, downloading, or purchasing any Content, you agree to be bound by the Terms and Conditions set out below ("Terms and Conditions"). If you do not agree to these Terms and Conditions, do not access the www.guestezee.com site or download any Content.'),
        SizedBox(height: 16),
        _buildSectionTitle('General Disclaimers'),
        SizedBox(height: 12),
        _buildParagraph(
            'Guestvento Technology private limited technology division publishes Content on the www.guestezee.com site to be accurate and reliable, however, since the Content has been compiled from a variety of sources, it is provided to the readers "as is" and "as available". Guestvento Technology private limited Technology division ASSUMES NO RESPONSIBILITY TO ANYONE OR ANY THIRD PARTY FOR ANY ERRORS OR OMISSIONS OF ANY KIND IN THE CONTENT, AND DISCLAIMS ALL WARRANTIES AND/OR CONDITIONS, EXPRESS OR IMPLIED, AS TO THE CONTENT AND TO ANY MATTER RELATING TO THE SITE, INCLUDING BUT NOT LIMITED TO, IMPLIED WARRANTIES AND/OR CONDITIONS OF NON INFRINGEMENT, MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.'),
        SizedBox(height: 12),
        _buildParagraph(
            'Links available on the www.guestezee.com site will allow you to link to websites not maintained or controlled by Guestvento Technology private limited technology division. These links are provided for your convenience – neither party is responsible for the content or online transactions of any linked site. Guestvento Technology private limited technology division uses reasonable efforts to ensure the accuracy of its Content on the www.guestezee.com site, but cannot and does not warrant the accuracy, completeness, non-infringement, merchantability or fitness for a particular purpose of any information or online transactions available through these links, and makes no representation or endorsement whatsoever about any other website which you may access through the www.guestezee.com site. It is your responsibility to ensure that any website you choose to use is free of potentially destructive items such as viruses.'),
        SizedBox(height: 16),
        _buildSectionTitle('Use of the Site'),
        SizedBox(height: 12),
        _buildParagraph(
            'You may not post, upload, publish, reproduce, transmit, or otherwise distribute information or other material on this www.guestezee.com'),
        _buildBulletPoint(
            'Constituting or encouraging conduct that would constitute a criminal offence or give rise to civil liability;'),
        _buildBulletPoint(
            'Which is protected by copyright, or other intellectual property right, or derivative works hereof, without obtaining permission of the copyright holder; or'),
        _buildBulletPoint(
            'Otherwise, use this www.guestezee.com site in a manner which is contrary to law or electronic etiquette, or which would adversely impact use of the www.guestezee.com or the Internet by other users, including the posting or transmitting of information or software containing viruses or other disruptive components.'),
        SizedBox(height: 16),
        _buildSectionTitle('Copyright'),
        SizedBox(height: 12),
        _buildParagraphOnce(
            'All Content published on or otherwise accessible through this www.guestezee.com site is protected by copyright. The Content, and the copyright in the Content, are owned or controlled by Guestvento Technology private limited technology division or its content suppliers. You may only use or reproduce the information in the Content for your own personal, non-commercial or educational use. The Content may not be otherwise used, reproduced, broadcast, published, or retransmitted without the prior written permission of the copyright holder. You must abide by all copyright notices, information and restrictions contained in any Content on or accessed through the www.guestezee.com site, and maintain such notices in the Content.'),
        _buildParagraph(
            'Postings related to Demo, About, Brochure and Hotels enrolling and their hotel details etc which are posted by the registered members, are the sole property of Guestvento Technology and reserves its right to repost in any social media/other sites.'),
        SizedBox(height: 16),
        _buildSectionTitle('Trademarks'),
        SizedBox(height: 12),
        _buildParagraph(
            'www.guestezee.com™ is a registered trademark of Guestvento Technology private limited, Technology division in India. All other products, services and company names mentioned in the www.guestezee.com site may be trademarks of their respective owners. You may not use any trademark displayed on the www.guestezee.com site without the written permission of Guestvento Technology\'s Technology division or the relevant owner of the trademark.'),
        SizedBox(height: 16),
        _buildSectionTitle('Payments'),
        SizedBox(height: 12),
        _buildParagraph(
            'Guestvento Technology\'s technology division is authorised to collect payments from the Members (Hotels and Customers) / Advertisers online thru approved 3rd party payment gateway.'),
        SizedBox(height: 16),
        _buildSectionTitle('Privacy and Confidential Information'),
        SizedBox(height: 12),
        _buildParagraph(
            'Guestvento Technology\'s Technology division Privacy and Security Policy is a binding part of these Terms and Conditions. The Privacy and Security Policy is available at this website.'),
        SizedBox(height: 16),
        _buildSectionTitle('Indemnity'),
        SizedBox(height: 12),
        _buildParagraph(
            'You agree to defend, indemnify and hold Guestvento Technology\'s technology division and its related companies harmless from any and all liabilities, costs and expenses, including reasonable attorney\'s fees, related to any violation of these Terms and Conditions by you or users of your account, or in connection with the use of www.guestezee.com site or the placement or transmission of any information or other materials on this site by you or users of your account.'),
        SizedBox(height: 16),
        _buildSectionTitle('Changes'),
        SizedBox(height: 12),
        _buildParagraph(
            'Guestvento Technology\'s media division reserves the right to change or remove any Content from the website www.guestezee.com, in whole or in part, at its sole discretion, at any time, without notice. Guestvento Technology\'s technology division reserves the right to change or modify these Terms and Conditions and its Privacy and Security Policy at any time, without notice, and such changes will become effective immediately from the date in which they are posted on the site.'),
        SizedBox(height: 16),
        _buildSectionTitle('Miscellaneous'),
        SizedBox(height: 12),
        _buildParagraph(
            'Terms and Conditions, including Guestvento Technology\'s technology division Privacy and Security Policy and other documents referenced herein, constitute the entire agreement between Guestvento Technology\'s technology division and you with respect to your use of the site. Guestvento Technology\'s technology division failure to insist upon or enforce strict performance of any provision of the Agreement shall not be construed as a waiver of any provision or right. If any of the Terms and Conditions is determined to be void, invalid or otherwise unenforceable by a court of competent jurisdiction, such determination shall not affect the remaining provisions hereof. This Agreement shall be governed by and construed in accordance with the laws of India, with the court of Chennai as jurisdiction. The parties have required that these Terms and Conditions and all related documents be drawn up in English.'),
        SizedBox(height: 20),
      ],
    );
  }

  Widget _buildPrivacyPolicyContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Privacy Policy – Guestvento Technology Pvt Ltd'),
        SizedBox(height: 12),
        _buildParagraph(
            'Guestvento Technology Private Limited (hereinafter "GUESTEZEE") recognizes the importance of privacy of its users and also of maintaining confidentiality of the information provided by its users as a responsible data controller and data processer.'),
        _buildParagraph(
            'This Privacy Policy provides for the practices for handling and securing user\'s Personal Information (defined hereunder) by GUESTEZEE and its subsidiaries and affiliates.'),
        _buildParagraph(
            'This Privacy Policy is applicable to any person (\'User\') who purchase, intend to purchase, or inquire about any product(s) or service(s) made available by GUESTEZEE through any of GUESTEZEE\'s customer interface channels including its website, mobile site, mobile app.'),
        _buildParagraph(
            'For the purpose of this Privacy Policy, wherever the context so requires "you" or "your" shall mean User and the term "we", "us", "our" shall mean GUESTEZEE. For the purpose of this Privacy Policy, Website means the website(s), mobile site(s) and mobile app(s).'),
        _buildParagraph(
            'By using or accessing the Website or App, the User hereby agrees with the terms of this Privacy Policy and the contents herein. If you disagree with this Privacy Policy please do not use or access our Website or App.'),
        _buildParagraph(
            'This Privacy Policy does not apply to any website(s), mobile sites and mobile apps of third parties, even if their websites/products are linked to our Website. User should take note that information and privacy practices of GUESTEZEE\'s business partners, advertisers, sponsors or other sites to which GUESTEZEE provides hyperlink(s), may be materially different from this Privacy Policy. Accordingly, it is recommended that you review the privacy statements and policies of any such third parties with whom they interact.'),
        _buildParagraph(
            'This Privacy Policy is an integral part of your User Agreement with GUESTEZEE and all capitalized terms used, but not otherwise defined herein, shall have the respective meanings as subscribed to them in the User Agreement.'),
        SizedBox(height: 24),
        _buildSectionTitle('Account Deletion'),
        SizedBox(height: 12),
        _buildParagraph(
            'If you wish to request the deletion of your account and personal data, please contact us using the information provided below. We will process your request in accordance with applicable data protection laws.'),
        SizedBox(height: 20),
        Container(
          padding: EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary.withOpacity(0.1),
                Theme.of(context).colorScheme.secondary.withOpacity(0.1),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.contact_mail,
                      color: Theme.of(context).colorScheme.primary, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'GET IN TOUCH',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 20),
              _buildContactItem(
                  context, Icons.phone, 'Call', '+91 90030 44445'),
              SizedBox(height: 16),
              _buildContactItem(
                  context, Icons.email, 'Email', 'enquiry@guestezee.com'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildContactItem(
      BuildContext context, IconData icon, String label, String value) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: Theme.of(context).colorScheme.primary),
        ),
        SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 4),
              Text(
                value,
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
  }

  Widget _buildParagraph(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.black87,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildParagraphOnce(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 14,
          color: Colors.black87,
          height: 1.6,
        ),
      ),
    );
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: EdgeInsets.only(left: 16, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: TextStyle(fontSize: 18, color: Colors.black87)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 14,
                color: Colors.black87,
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
