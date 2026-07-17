// skincare_profiles_screen.dart
import 'package:flutter/material.dart';
import '../models/product_tracker.dart';
import '../utils/app_prefs.dart';
import '../app_theme.dart';
import '../widgets/clinical_section_header.dart';
import 'active_skincare_details_screen.dart';
import 'log_skincare_product_screen.dart';

class SkincareProfilesScreen extends StatefulWidget {
  const SkincareProfilesScreen({super.key});

  @override
  State<SkincareProfilesScreen> createState() => _SkincareProfilesScreenState();
}

class _SkincareProfilesScreenState extends State<SkincareProfilesScreen> {
  List<TrackedProduct> products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final loaded = await AppPrefs.getTrackedProducts();
      if (!mounted) return;
      setState(() {
        products = loaded;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = MyApp.textBrown;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: ClinicalAppBarTitle(
          title: 'Skincare Profiles',
          eyebrow: 'Patient regimens',
          color: textColor,
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
          color: textColor,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          MyApp.champagne,
                          MyApp.roseGold.withValues(alpha: 0.15),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your Skincare Products',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Track products, monitor progress, and maintain results.',
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.75),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  const ClinicalSectionHeader(
                    icon: Icons.inventory_2_outlined,
                    title: 'Tracked Products',
                    eyebrow: 'Your shelf',
                  ),
                  const SizedBox(height: 12),

                  if (products.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 32,
                      ),
                      decoration: MyApp.surfaceCardDecoration(
                        tintOpacity: 0.06,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: MyApp.roseGold.withValues(alpha: 0.10),
                              border: Border.all(
                                color: MyApp.roseGold.withValues(alpha: 0.32),
                                width: 1,
                              ),
                            ),
                            child: Icon(
                              Icons.inventory_2_outlined,
                              color: MyApp.roseGold,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No skincare products yet',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: MyApp.clinicalNavy,
                              letterSpacing: 0.1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Log the cleansers, serums, and SPF you actually use. Your shelf powers smarter recommendations and progress tracking.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              color: MyApp.clinicalSlate,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: products
                          .map((product) => _buildProductCard(product))
                          .toList(),
                    ),

                  const SizedBox(height: 32),

                  ElevatedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const LogSkincareProductScreen(),
                        ),
                      );
                      if (result == true) await _loadProducts();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MyApp.goldShimmer,
                      foregroundColor: textColor,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('Log New Skincare Product'),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProductCard(TrackedProduct product) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ActiveSkincareDetailsScreen(product: product),
            ),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      product.brand.isNotEmpty
                          ? product.brand
                          : 'No brand recorded',
                    ),
                    Text(
                      'Started: ${product.startDate.toLocal().toString().split(' ')[0]}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 14),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.orange, size: 28),
            ],
          ),
        ),
      ),
    );
  }
}
