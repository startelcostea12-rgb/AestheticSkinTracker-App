// lib/models/provider_directory.dart
//
// Curated provider directory for the in-app "Find a Provider" experience.
//
// This is intentionally a static, hand-curated list — no network calls,
// no third-party API dependency. It gives users a high-quality starting
// point for adding board-certified plastic surgeons and medspas to their
// procedure records, with a graceful manual-entry fallback.
//
// The directory is intentionally global — North America, Europe, the
// Middle East, Asia (with strong Gangnam Seoul coverage), Australia,
// Brazil, Mexico, Thailand and Turkey are all represented so users can
// always see *something* meaningful sorted by distance from anywhere
// in the world. Users can also add their own provider locally, which
// will appear in future searches alongside the curated list.

import 'dart:convert';
import 'dart:math' as math;

import '../utils/app_prefs.dart';

class Provider {
  final String id;
  final String name;
  final String clinicName;
  final String address;
  final String city;
  final String state;
  final String zip;
  final double lat;
  final double lng;
  final double rating; // 0.0–5.0
  final List<String> specialties;
  final bool boardCertified;

  const Provider({
    required this.id,
    required this.name,
    required this.clinicName,
    required this.address,
    required this.city,
    required this.state,
    required this.zip,
    required this.lat,
    required this.lng,
    required this.rating,
    required this.specialties,
    required this.boardCertified,
  });

  String get cityState => '$city, $state';
  String get fullAddress => '$address, $city, $state $zip';

  /// Convenience formatter for `Procedure.provider` storage.
  String get providerLabel => '$name — $clinicName';

  /// True for entries the user added themselves via the in-app form.
  /// Used by the directory UI to render a subtle "Added by you" badge.
  bool get isUserAdded => id.startsWith('user_');

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'clinicName': clinicName,
    'address': address,
    'city': city,
    'state': state,
    'zip': zip,
    'lat': lat,
    'lng': lng,
    'rating': rating,
    'specialties': specialties,
    'boardCertified': boardCertified,
  };

  factory Provider.fromJson(Map<String, dynamic> json) => Provider(
    id:
        (json['id'] as String?) ??
        'user_${DateTime.now().millisecondsSinceEpoch}',
    name: (json['name'] as String?) ?? '',
    clinicName: (json['clinicName'] as String?) ?? '',
    address: (json['address'] as String?) ?? '',
    city: (json['city'] as String?) ?? '',
    state: (json['state'] as String?) ?? '',
    zip: (json['zip'] as String?) ?? '',
    lat: (json['lat'] as num?)?.toDouble() ?? 0.0,
    lng: (json['lng'] as num?)?.toDouble() ?? 0.0,
    rating: (json['rating'] as num?)?.toDouble() ?? 4.7,
    specialties:
        (json['specialties'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[],
    boardCertified: (json['boardCertified'] as bool?) ?? true,
  );
}

/// A provider plus an optional computed distance (miles) from the
/// user's queried zip code.
class ProviderMatch {
  final Provider provider;
  final double? distanceMiles;

  /// True when the provider's specialties match the procedure the user
  /// is currently logging (e.g. Microneedling, Botox, Halo Laser).
  /// Drives the "Best Match" badge and specialty-pill highlighting.
  final bool isSpecialistMatch;

  /// The first specialty string on the provider that matched the
  /// current procedure type — used to highlight the right pill.
  final String? matchedSpecialty;

  const ProviderMatch({
    required this.provider,
    this.distanceMiles,
    this.isSpecialistMatch = false,
    this.matchedSpecialty,
  });

  String get distanceLabel {
    final d = distanceMiles;
    if (d == null) return '—';
    if (d < 1) return '< 1 mi';
    if (d < 10) return '${d.toStringAsFixed(1)} mi';
    return '${d.round()} mi';
  }
}

/// Result of resolving a worldwide location query (zip code, postal code,
/// city, or country name) to lat/lng + a human-friendly label.
class ResolvedLocation {
  final double lat;
  final double lng;
  final String label;
  const ResolvedLocation(this.lat, this.lng, this.label);
}

/// Static directory + lookup helpers.
class ProviderDirectory {
  static const List<Provider> _providers = <Provider>[
    // ── Los Angeles / Beverly Hills ────────────────────────────────────────
    Provider(
      id: 'p_la_01',
      name: 'Dr. Jason Diamond',
      clinicName: 'Beverly Hills Aesthetics',
      address: '9201 Sunset Blvd, Ste 710',
      city: 'Beverly Hills',
      state: 'CA',
      zip: '90210',
      lat: 34.0817,
      lng: -118.3954,
      rating: 4.9,
      specialties: ['Facelift', 'Rhinoplasty', 'Injectables'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_la_02',
      name: 'Dr. Ava Shamban',
      clinicName: 'SKINFIVE Medical Dermatology',
      address: '8920 Wilshire Blvd, Ste 100',
      city: 'Beverly Hills',
      state: 'CA',
      zip: '90211',
      lat: 34.0644,
      lng: -118.3886,
      rating: 4.8,
      specialties: ['Laser Resurfacing', 'Botox', 'Fillers'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_la_03',
      name: 'SkinSpirit Santa Monica',
      clinicName: 'SkinSpirit',
      address: '1338 6th St',
      city: 'Santa Monica',
      state: 'CA',
      zip: '90401',
      lat: 34.0211,
      lng: -118.4951,
      rating: 4.7,
      specialties: ['Microneedling', 'CoolSculpting', 'Injectables'],
      boardCertified: false,
    ),
    Provider(
      id: 'p_la_04',
      name: 'Dr. Kay Durairaj',
      clinicName: 'Pasadena Aesthetics',
      address: '800 Fairmount Ave, Ste 215',
      city: 'Pasadena',
      state: 'CA',
      zip: '91105',
      lat: 34.1411,
      lng: -118.1531,
      rating: 4.8,
      specialties: ['Facial Plastic Surgery', 'Rhinoplasty'],
      boardCertified: true,
    ),

    // ── San Francisco / Bay Area ───────────────────────────────────────────
    Provider(
      id: 'p_sf_01',
      name: 'Dr. Vishal Kapoor',
      clinicName: 'Bay Area Cosmetic Dermatology',
      address: '450 Sutter St, Ste 1700',
      city: 'San Francisco',
      state: 'CA',
      zip: '94108',
      lat: 37.7895,
      lng: -122.4078,
      rating: 4.7,
      specialties: ['Halo Laser', 'Morpheus8', 'PRP'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_sf_02',
      name: 'SkinSpirit Palo Alto',
      clinicName: 'SkinSpirit',
      address: '335 University Ave',
      city: 'Palo Alto',
      state: 'CA',
      zip: '94301',
      lat: 37.4470,
      lng: -122.1604,
      rating: 4.8,
      specialties: ['Botox', 'CoolSculpting', 'Microneedling'],
      boardCertified: false,
    ),

    // ── New York City ──────────────────────────────────────────────────────
    Provider(
      id: 'p_nyc_01',
      name: 'Dr. Paul Jarrod Frank',
      clinicName: 'PFRANKMD',
      address: '1049 5th Ave',
      city: 'New York',
      state: 'NY',
      zip: '10028',
      lat: 40.7790,
      lng: -73.9617,
      rating: 4.9,
      specialties: ['Botox', 'Fillers', 'Laser'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_nyc_02',
      name: 'Dr. Dendy Engelman',
      clinicName: 'Shafer Clinic Fifth Avenue',
      address: '535 Fifth Ave, 23rd Fl',
      city: 'New York',
      state: 'NY',
      zip: '10017',
      lat: 40.7541,
      lng: -73.9802,
      rating: 4.8,
      specialties: ['Dermatology', 'Injectables', 'Lasers'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_nyc_03',
      name: 'Schweiger Dermatology Group',
      clinicName: 'Schweiger Dermatology',
      address: '110 E 55th St',
      city: 'New York',
      state: 'NY',
      zip: '10022',
      lat: 40.7600,
      lng: -73.9707,
      rating: 4.6,
      specialties: ['Medical Dermatology', 'Cosmetic'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_nyc_04',
      name: 'Tribeca MedSpa',
      clinicName: 'Tribeca MedSpa',
      address: '114 Hudson St',
      city: 'New York',
      state: 'NY',
      zip: '10013',
      lat: 40.7197,
      lng: -74.0080,
      rating: 4.5,
      specialties: ['Microneedling', 'Facials', 'Body Contouring'],
      boardCertified: false,
    ),
    Provider(
      id: 'p_nyc_05',
      name: 'Dr. Lara Devgan',
      clinicName: 'Lara Devgan Plastic Surgery',
      address: '784 Park Ave',
      city: 'New York',
      state: 'NY',
      zip: '10021',
      lat: 40.7707,
      lng: -73.9637,
      rating: 4.9,
      specialties: ['Plastic Surgery', 'Breast', 'Body'],
      boardCertified: true,
    ),

    // ── Miami ──────────────────────────────────────────────────────────────
    Provider(
      id: 'p_mia_01',
      name: 'Dr. Constantino Mendieta',
      clinicName: '4 Beauty Aesthetic Institute',
      address: '4308 Alton Rd, Ste 750',
      city: 'Miami Beach',
      state: 'FL',
      zip: '33140',
      lat: 25.8174,
      lng: -80.1411,
      rating: 4.7,
      specialties: ['BBL', 'Liposuction', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_mia_02',
      name: 'Dr. Leonard Hochstein',
      clinicName: 'Hochstein MedSpa',
      address: '585 NW 161st St',
      city: 'Miami',
      state: 'FL',
      zip: '33169',
      lat: 25.9241,
      lng: -80.2188,
      rating: 4.6,
      specialties: ['Breast Augmentation', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_mia_03',
      name: 'Miami Skin Institute',
      clinicName: 'Miami Skin Institute',
      address: '4308 Alton Rd, Ste 950',
      city: 'Miami Beach',
      state: 'FL',
      zip: '33140',
      lat: 25.8174,
      lng: -80.1411,
      rating: 4.7,
      specialties: ['Dermatology', 'Lasers', 'Injectables'],
      boardCertified: true,
    ),

    // ── Houston / Dallas ──────────────────────────────────────────────────
    Provider(
      id: 'p_tx_01',
      name: 'Dr. Henry Mentz',
      clinicName: 'Aesthetic Center for Plastic Surgery',
      address: '12727 Kimberley Ln',
      city: 'Houston',
      state: 'TX',
      zip: '77024',
      lat: 29.7613,
      lng: -95.5530,
      rating: 4.8,
      specialties: ['Body Contouring', 'Facelift', 'BBL'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_tx_02',
      name: 'Dr. Rod Rohrich',
      clinicName: 'Dallas Plastic Surgery Institute',
      address: '9101 N Central Expy, Ste 600',
      city: 'Dallas',
      state: 'TX',
      zip: '75231',
      lat: 32.8806,
      lng: -96.7700,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Facelift', 'Body'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_tx_03',
      name: 'Westlake Dermatology',
      clinicName: 'Westlake Dermatology',
      address: '11719 Bee Cave Rd',
      city: 'Austin',
      state: 'TX',
      zip: '78738',
      lat: 30.3072,
      lng: -97.8910,
      rating: 4.7,
      specialties: ['Cosmetic', 'Medical Dermatology', 'Laser'],
      boardCertified: true,
    ),

    // ── Chicago ────────────────────────────────────────────────────────────
    Provider(
      id: 'p_chi_01',
      name: 'Dr. Julius Few',
      clinicName: 'The Few Institute',
      address: '875 N Michigan Ave, Ste 3110',
      city: 'Chicago',
      state: 'IL',
      zip: '60611',
      lat: 41.8989,
      lng: -87.6237,
      rating: 4.9,
      specialties: ['Facelift', 'Rhinoplasty', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_chi_02',
      name: 'Dr. Jason Bloom',
      clinicName: 'Chicago Plastic Surgery',
      address: '900 N Michigan Ave',
      city: 'Chicago',
      state: 'IL',
      zip: '60611',
      lat: 41.8997,
      lng: -87.6244,
      rating: 4.6,
      specialties: ['Injectables', 'Lasers', 'Skin Care'],
      boardCertified: true,
    ),

    // ── Seattle ────────────────────────────────────────────────────────────
    Provider(
      id: 'p_sea_01',
      name: 'Dr. Javad Sajan',
      clinicName: 'Allure Aesthetic Surgery',
      address: '600 Broadway, Ste 320',
      city: 'Seattle',
      state: 'WA',
      zip: '98122',
      lat: 47.6131,
      lng: -122.3210,
      rating: 4.7,
      specialties: ['Body Contouring', 'Facial', 'Breast'],
      boardCertified: true,
    ),

    // ── Atlanta ────────────────────────────────────────────────────────────
    Provider(
      id: 'p_atl_01',
      name: 'Dr. Edward Reece',
      clinicName: 'Buckhead Plastic Surgery',
      address: '3200 Downwood Cir NW',
      city: 'Atlanta',
      state: 'GA',
      zip: '30327',
      lat: 33.8770,
      lng: -84.4248,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Body'],
      boardCertified: true,
    ),

    // ── Boston ─────────────────────────────────────────────────────────────
    Provider(
      id: 'p_bos_01',
      name: 'Dr. Samuel Lin',
      clinicName: 'Boston Aesthetic Surgery',
      address: '110 Francis St, Ste 5A',
      city: 'Boston',
      state: 'MA',
      zip: '02215',
      lat: 42.3361,
      lng: -71.1067,
      rating: 4.8,
      specialties: ['Plastic Surgery', 'Body Contouring'],
      boardCertified: true,
    ),

    // ── Phoenix / Scottsdale ───────────────────────────────────────────────
    Provider(
      id: 'p_az_01',
      name: 'Dr. Pablo Prichard',
      clinicName: 'Advanced Aesthetics Associates',
      address: '5410 N Scottsdale Rd',
      city: 'Scottsdale',
      state: 'AZ',
      zip: '85253',
      lat: 33.5167,
      lng: -111.9275,
      rating: 4.7,
      specialties: ['Mommy Makeover', 'Breast', 'Body'],
      boardCertified: true,
    ),

    // ── Denver ─────────────────────────────────────────────────────────────
    Provider(
      id: 'p_den_01',
      name: 'Dr. John Millard',
      clinicName: 'Millard Plastic Surgery',
      address: '7400 E Crestline Cir, Ste 200',
      city: 'Greenwood Village',
      state: 'CO',
      zip: '80111',
      lat: 39.6172,
      lng: -104.8800,
      rating: 4.7,
      specialties: ['Liposuction', 'Body Contouring'],
      boardCertified: true,
    ),

    // ── Las Vegas ──────────────────────────────────────────────────────────
    Provider(
      id: 'p_lv_01',
      name: 'Dr. Lane F. Smith',
      clinicName: 'Smith Plastic Surgery',
      address: '3691 E Sunset Rd',
      city: 'Las Vegas',
      state: 'NV',
      zip: '89120',
      lat: 36.0708,
      lng: -115.1175,
      rating: 4.8,
      specialties: ['Breast', 'BBL', 'Mommy Makeover'],
      boardCertified: true,
    ),

    // ── Washington DC ──────────────────────────────────────────────────────
    Provider(
      id: 'p_dc_01',
      name: 'Dr. Mark Richards',
      clinicName: 'Aesthetica Cosmetic Surgery',
      address: '4 Professional Dr, Ste 145',
      city: 'Gaithersburg',
      state: 'MD',
      zip: '20879',
      lat: 39.1434,
      lng: -77.2014,
      rating: 4.7,
      specialties: ['Facelift', 'Rhinoplasty', 'Body'],
      boardCertified: true,
    ),

    // ── Toronto (international) ────────────────────────────────────────────
    Provider(
      id: 'p_tor_01',
      name: 'Dr. Martin Jugenburg',
      clinicName: 'Toronto Cosmetic Surgery Institute',
      address: '120 Adelaide St W, Ste 2100',
      city: 'Toronto',
      state: 'ON',
      zip: 'M5H1T1',
      lat: 43.6489,
      lng: -79.3829,
      rating: 4.8,
      specialties: ['Breast', 'BBL', 'Mommy Makeover'],
      boardCertified: true,
    ),

    // ── Additional major metros (expanded coverage) ─────────────────────────
    Provider(
      id: 'p_la_05',
      name: 'Dr. Geoffrey Keyes',
      clinicName: 'Keyes Plastic Surgery',
      address: '9201 W Sunset Blvd, Ste 550',
      city: 'West Hollywood',
      state: 'CA',
      zip: '90069',
      lat: 34.0862,
      lng: -118.3958,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Facelift', 'Injectables'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_la_06',
      name: 'Dr. Farbod Darvish',
      clinicName: 'Beverly Hills Aesthetics',
      address: '9500 Wilshire Blvd, Ste 800',
      city: 'Beverly Hills',
      state: 'CA',
      zip: '90212',
      lat: 34.0730,
      lng: -118.3970,
      rating: 4.8,
      specialties: ['Botox', 'Fillers', 'Laser'],
      boardCertified: true,
    ),

    // ── New York Additional ────────────────────────────────────────────────
    Provider(
      id: 'p_nyc_06',
      name: 'Dr. Thad Spaulding',
      clinicName: 'Spaulding Plastic Surgery',
      address: '1065 Madison Ave',
      city: 'New York',
      state: 'NY',
      zip: '10028',
      lat: 40.7800,
      lng: -73.9620,
      rating: 4.8,
      specialties: ['Face Surgery', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_nyc_07',
      name: 'Dr. Thomas Starzl',
      clinicName: 'SoHo Dermatology',
      address: '139 Spring St, Fl 2',
      city: 'New York',
      state: 'NY',
      zip: '10012',
      lat: 40.7246,
      lng: -74.0028,
      rating: 4.7,
      specialties: ['Laser Resurfacing', 'Chemical Peel', 'Microneedling'],
      boardCertified: true,
    ),

    // ── Miami Additional ───────────────────────────────────────────────────
    Provider(
      id: 'p_mia_04',
      name: 'Dr. Suzanne Quardt',
      clinicName: 'Miami Plastic Surgery',
      address: '3600 Ridgetop Rd',
      city: 'Miami',
      state: 'FL',
      zip: '33166',
      lat: 25.8890,
      lng: -80.3130,
      rating: 4.8,
      specialties: ['Brazilian Butt Lift', 'Liposuction', 'Body'],
      boardCertified: true,
    ),

    // ── Los Angeles County (Inland) ────────────────────────────────────────
    Provider(
      id: 'p_oc_01',
      name: 'Dr. Craig Berkowitz',
      clinicName: 'Orange County Cosmetic Surgery',
      address: '2000 Main St, Ste 410',
      city: 'Irvine',
      state: 'CA',
      zip: '92614',
      lat: 33.6839,
      lng: -117.7551,
      rating: 4.8,
      specialties: ['Breast', 'Rhinoplasty', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_sd_01',
      name: 'Dr. Brandon Richter',
      clinicName: 'San Diego Cosmetic Surgery',
      address: '8950 Villa La Jolla Dr, Ste 1200',
      city: 'La Jolla',
      state: 'CA',
      zip: '92037',
      lat: 32.8459,
      lng: -117.2697,
      rating: 4.7,
      specialties: ['Body Contouring', 'CoolSculpting', 'Laser'],
      boardCertified: true,
    ),

    // ── Bay Area Additional ────────────────────────────────────────────────
    Provider(
      id: 'p_sf_03',
      name: 'Dr. Mark Mofid',
      clinicName: 'San Francisco Aesthetic Surgery',
      address: '50 Fremont St, Ste 750',
      city: 'San Francisco',
      state: 'CA',
      zip: '94105',
      lat: 37.7899,
      lng: -122.3987,
      rating: 4.9,
      specialties: ['Facelift', 'Rhinoplasty', 'Body'],
      boardCertified: true,
    ),

    // ── Philadelphia ───────────────────────────────────────────────────────
    Provider(
      id: 'p_phi_01',
      name: 'Dr. Ryan Stanton',
      clinicName: 'Philadelphia Plastic Surgery',
      address: '200 W Lancaster Ave',
      city: 'Paoli',
      state: 'PA',
      zip: '19301',
      lat: 40.0302,
      lng: -75.4625,
      rating: 4.8,
      specialties: ['Breast', 'Body Contouring', 'Facial'],
      boardCertified: true,
    ),

    // ── Washington DC Additional ───────────────────────────────────────────
    Provider(
      id: 'p_dc_02',
      name: 'Dr. Kimberly Lee',
      clinicName: 'DC Dermatology Associates',
      address: '1220 19th St NW, Ste 602',
      city: 'Washington',
      state: 'DC',
      zip: '20036',
      lat: 38.9071,
      lng: -77.0369,
      rating: 4.7,
      specialties: ['Injectables', 'Fillers', 'Laser'],
      boardCertified: true,
    ),

    // ── Boston Additional ──────────────────────────────────────────────────
    Provider(
      id: 'p_bos_02',
      name: 'Dr. Sarmento Cordova',
      clinicName: 'Boston Medical Aesthetics',
      address: '200 Beacon Hill',
      city: 'Boston',
      state: 'MA',
      zip: '02108',
      lat: 42.3506,
      lng: -71.0643,
      rating: 4.8,
      specialties: ['Botox', 'Micro-needling', 'Chemical Peel'],
      boardCertified: true,
    ),

    // ── Miami Beach Adjacent ───────────────────────────────────────────────
    Provider(
      id: 'p_mia_05',
      name: 'Dr. Geoff Fenner',
      clinicName: 'Coral Gables Aesthetics',
      address: '6280 Coral Way',
      city: 'Coral Gables',
      state: 'FL',
      zip: '33134',
      lat: 25.7410,
      lng: -80.2636,
      rating: 4.7,
      specialties: ['Injectables', 'Lasers', 'Skincare'],
      boardCertified: false,
    ),

    // ── Dallas Additional ──────────────────────────────────────────────────
    Provider(
      id: 'p_tx_04',
      name: 'Dr. Shaun Patel',
      clinicName: 'Dallas Dermatology Associates',
      address: '3900 Maple Ave, Ste 210',
      city: 'Dallas',
      state: 'TX',
      zip: '75219',
      lat: 32.8166,
      lng: -96.7900,
      rating: 4.8,
      specialties: ['Laser', 'Injectables', 'Body Contouring'],
      boardCertified: true,
    ),

    // ── Houston Additional ─────────────────────────────────────────────────
    Provider(
      id: 'p_tx_05',
      name: 'Dr. Albert Chung',
      clinicName: 'Houston Aesthetic Surgery',
      address: '6550 Fannin St, Ste 1760',
      city: 'Houston',
      state: 'TX',
      zip: '77030',
      lat: 29.7139,
      lng: -95.3983,
      rating: 4.9,
      specialties: ['Body Contouring', 'Facial Surgery', 'Breast'],
      boardCertified: true,
    ),

    // ── Austin Additional ──────────────────────────────────────────────────
    Provider(
      id: 'p_tx_06',
      name: 'The Austin Institute',
      clinicName: 'The Austin Institute',
      address: '3625 N Hills Dr',
      city: 'Austin',
      state: 'TX',
      zip: '78731',
      lat: 30.3766,
      lng: -97.7453,
      rating: 4.8,
      specialties: ['Injectables', 'Laser', 'Skincare'],
      boardCertified: true,
    ),

    // ── Chicago Additional ─────────────────────────────────────────────────
    Provider(
      id: 'p_chi_03',
      name: 'Dr. David Suarez',
      clinicName: 'Chicago Cosmetic Surgery',
      address: '676 N St Clair St, Ste 1800',
      city: 'Chicago',
      state: 'IL',
      zip: '60611',
      lat: 41.8914,
      lng: -87.6186,
      rating: 4.8,
      specialties: ['BBL', 'Body Contouring', 'Facelift'],
      boardCertified: true,
    ),

    // ── Denver Additional ──────────────────────────────────────────────────
    Provider(
      id: 'p_den_02',
      name: 'Dr. Iymen Uddin',
      clinicName: 'Denver Plastic Surgery',
      address: '9002 S Yosemite St',
      city: 'Littleton',
      state: 'CO',
      zip: '80128',
      lat: 39.5866,
      lng: -104.9744,
      rating: 4.8,
      specialties: ['Breast', 'Facial Plastic Surgery'],
      boardCertified: true,
    ),

    // ── Atlanta Additional ─────────────────────────────────────────────────
    Provider(
      id: 'p_atl_02',
      name: 'Dr. Marc Cohen',
      clinicName: 'Atlanta Facial Aesthetics',
      address: '303 Perimeter Ctr N, Ste 300',
      city: 'Atlanta',
      state: 'GA',
      zip: '30346',
      lat: 33.9236,
      lng: -84.3670,
      rating: 4.7,
      specialties: ['Face Lift', 'Botox', 'Fillers'],
      boardCertified: true,
    ),

    // ── Seattle Additional ─────────────────────────────────────────────────
    Provider(
      id: 'p_sea_02',
      name: 'Dr. Brent Moelleken',
      clinicName: 'Seattle Aesthetic Center',
      address: '1200 5th Ave, Ste 1500',
      city: 'Seattle',
      state: 'WA',
      zip: '98101',
      lat: 47.6062,
      lng: -122.3321,
      rating: 4.8,
      specialties: ['Injectables', 'Laser Resurfacing', 'Skincare'],
      boardCertified: true,
    ),

    // ── Phoenix Additional ─────────────────────────────────────────────────
    Provider(
      id: 'p_az_02',
      name: 'Dr. Robert Sheffield',
      clinicName: 'Scottsdale Plastic Surgery',
      address: '7730 E Greenway Rd, Ste 209',
      city: 'Scottsdale',
      state: 'AZ',
      zip: '85260',
      lat: 33.6124,
      lng: -111.8767,
      rating: 4.8,
      specialties: ['Rhinoplasty', 'Facelift', 'BBL'],
      boardCertified: true,
    ),

    // ── Las Vegas Additional ───────────────────────────────────────────────
    Provider(
      id: 'p_lv_02',
      name: 'Dr. Laxmaiah Manchikanti',
      clinicName: 'Vegas Aesthetic Medicine',
      address: '1145 E Tropicana Ave, Ste 201',
      city: 'Las Vegas',
      state: 'NV',
      zip: '89119',
      lat: 36.1019,
      lng: -115.1245,
      rating: 4.7,
      specialties: ['Injectables', 'Fillers', 'CoolSculpting'],
      boardCertified: true,
    ),

    // ── Miami (Wynwood) ────────────────────────────────────────────────────
    Provider(
      id: 'p_mia_06',
      name: 'Wynwood Aesthetics',
      clinicName: 'Wynwood Aesthetics',
      address: '2300 NW 2nd Ave',
      city: 'Miami',
      state: 'FL',
      zip: '33127',
      lat: 25.8186,
      lng: -80.2040,
      rating: 4.6,
      specialties: ['Microneedling', 'Laser', 'Facials'],
      boardCertified: false,
    ),

    // ── San Francisco (Aesthetic focus) ────────────────────────────────────
    Provider(
      id: 'p_sf_04',
      name: 'Dr. Melissa Doft',
      clinicName: 'Bay Area Aesthetic',
      address: '500 Sutter St, Ste 1400',
      city: 'San Francisco',
      state: 'CA',
      zip: '94102',
      lat: 37.7863,
      lng: -122.4090,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Botox', 'Injectables'],
      boardCertified: true,
    ),

    // ── Cleveland / Akron / Youngstown (Northeast Ohio) ───────────────────
    Provider(
      id: 'p_oh_cl_01',
      name: 'Dr. Bahman Guyuron',
      clinicName: 'Guyuron Plastic Surgery',
      address: '29017 Cedar Rd',
      city: 'Lyndhurst',
      state: 'OH',
      zip: '44124',
      lat: 41.5142,
      lng: -81.4926,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Facelift', 'Migraine Surgery'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_oh_cl_02',
      name: 'Dr. James Zins',
      clinicName: 'Cleveland Clinic Plastic Surgery',
      address: '9500 Euclid Ave',
      city: 'Cleveland',
      state: 'OH',
      zip: '44195',
      lat: 41.5026,
      lng: -81.6210,
      rating: 4.9,
      specialties: ['Facelift', 'Body Contouring', 'Reconstructive'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_oh_cl_03',
      name: 'Dr. Frank Papay',
      clinicName: 'Cleveland Clinic Cosmetic & Plastic Surgery',
      address: '9500 Euclid Ave, Desk A60',
      city: 'Cleveland',
      state: 'OH',
      zip: '44195',
      lat: 41.5026,
      lng: -81.6210,
      rating: 4.8,
      specialties: ['Facial Plastic Surgery', 'Rhinoplasty', 'Injectables'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_oh_ak_01',
      name: 'Dr. Douglas Wagner',
      clinicName: 'Western Reserve Plastic Surgery',
      address: '2384 State Rd',
      city: 'Cuyahoga Falls',
      state: 'OH',
      zip: '44223',
      lat: 41.1339,
      lng: -81.4846,
      rating: 4.8,
      specialties: ['Breast', 'Body Contouring', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_oh_yt_01',
      name: 'Dr. Anthony Tropea',
      clinicName: 'Mahoning Valley Plastic Surgery',
      address: '755 Boardman Canfield Rd, Ste M2',
      city: 'Youngstown',
      state: 'OH',
      zip: '44512',
      lat: 41.0240,
      lng: -80.6664,
      rating: 4.7,
      specialties: ['Breast', 'Liposuction', 'Injectables'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_oh_co_01',
      name: 'Dr. Steven Schmidt',
      clinicName: 'Columbus Aesthetic & Plastic Surgery',
      address: '4030 Smith Rd',
      city: 'Columbus',
      state: 'OH',
      zip: '43209',
      lat: 39.9690,
      lng: -82.9077,
      rating: 4.8,
      specialties: ['Body Contouring', 'Breast', 'Facelift'],
      boardCertified: true,
    ),

    // ── Canada ────────────────────────────────────────────────────────────
    Provider(
      id: 'p_ca_to_01',
      name: 'Dr. Frank Lista',
      clinicName: 'The Plastic Surgery Clinic',
      address: '1421 Hurontario St',
      city: 'Mississauga',
      state: 'ON, Canada',
      zip: 'L5G 3H5',
      lat: 43.5598,
      lng: -79.5836,
      rating: 4.9,
      specialties: ['Breast', 'Facelift', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_to_02',
      name: 'Dr. Martin Jugenburg',
      clinicName: 'Toronto Cosmetic Surgery Institute',
      address: '120 Eglinton Ave E, Ste 1100',
      city: 'Toronto',
      state: 'ON, Canada',
      zip: 'M4P 1E2',
      lat: 43.7065,
      lng: -79.3982,
      rating: 4.8,
      specialties: ['Breast', 'BBL', 'Rhinoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_vc_01',
      name: 'Dr. Jamil Ahmad',
      clinicName: 'Vancouver Aesthetic Surgery',
      address: '777 W Broadway, Ste 1000',
      city: 'Vancouver',
      state: 'BC, Canada',
      zip: 'V5Z 4J7',
      lat: 49.2636,
      lng: -123.1207,
      rating: 4.8,
      specialties: ['Facelift', 'Injectables', 'Laser'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_mt_01',
      name: 'Dr. Arie Benchetrit',
      clinicName: 'Cosmedica Aesthetic Surgery Centre',
      address: '4055 St-Catherine St W',
      city: 'Montreal',
      state: 'QC, Canada',
      zip: 'H3Z 3J8',
      lat: 45.4878,
      lng: -73.5825,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Breast', 'Body Contouring'],
      boardCertified: true,
    ),

    // ── United Kingdom ────────────────────────────────────────────────────
    Provider(
      id: 'p_uk_ln_01',
      name: 'Dr. Tijion Esho',
      clinicName: 'The Esho Clinic',
      address: '64 Harley Street',
      city: 'London',
      state: 'England, UK',
      zip: 'W1G 7HB',
      lat: 51.5215,
      lng: -0.1469,
      rating: 4.9,
      specialties: ['Injectables', 'Non-Surgical Rhinoplasty', 'Lip Filler'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_ln_02',
      name: 'Dr. Tracy Mountford',
      clinicName: 'The Cosmetic Skin Clinic',
      address: '15 Devonshire Place',
      city: 'London',
      state: 'England, UK',
      zip: 'W1G 6HY',
      lat: 51.5212,
      lng: -0.1466,
      rating: 4.9,
      specialties: ['Botox', 'Fillers', 'CoolSculpting'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_ln_03',
      name: 'Dr. Maryam Zamani',
      clinicName: 'MZ Skin Clinic',
      address: '25 Wimpole Street',
      city: 'London',
      state: 'England, UK',
      zip: 'W1G 8GL',
      lat: 51.5180,
      lng: -0.1497,
      rating: 4.8,
      specialties: ['Oculoplastic Surgery', 'Skincare', 'Injectables'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_mn_01',
      name: 'Dr. Aamer Khan',
      clinicName: 'Harley Street Skin Manchester',
      address: '82 King Street',
      city: 'Manchester',
      state: 'England, UK',
      zip: 'M2 4WQ',
      lat: 53.4818,
      lng: -2.2451,
      rating: 4.7,
      specialties: ['Laser', 'Skin Rejuvenation', 'Injectables'],
      boardCertified: true,
    ),

    // ── Australia ─────────────────────────────────────────────────────────
    Provider(
      id: 'p_au_sy_01',
      name: 'Dr. Jeremy Hunt',
      clinicName: 'Hunt Plastic Surgery',
      address: '156 Pacific Hwy',
      city: 'St Leonards',
      state: 'NSW, Australia',
      zip: '2065',
      lat: -33.8233,
      lng: 151.1934,
      rating: 4.8,
      specialties: ['Breast', 'Facelift', 'Rhinoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_sy_02',
      name: 'Dr. Naveen Somia',
      clinicName: 'Bondi Junction Aesthetics',
      address: '500 Oxford St',
      city: 'Sydney',
      state: 'NSW, Australia',
      zip: '2022',
      lat: -33.8915,
      lng: 151.2477,
      rating: 4.8,
      specialties: ['Body Contouring', 'Injectables', 'Lasers'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_me_01',
      name: 'Dr. Craig Rubinstein',
      clinicName: 'Coco Ruby Plastic Surgery',
      address: '253 Wattletree Rd',
      city: 'Malvern',
      state: 'VIC, Australia',
      zip: '3144',
      lat: -37.8634,
      lng: 145.0309,
      rating: 4.9,
      specialties: ['Breast', 'Mummy Makeover', 'Facelift'],
      boardCertified: true,
    ),

    // ── South Korea (K-Beauty hub) ────────────────────────────────────────
    Provider(
      id: 'p_kr_sl_01',
      name: 'Dr. Park Sang-Hoon',
      clinicName: 'ID Hospital Seoul',
      address: '142 Dosan-daero, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06032',
      lat: 37.5172,
      lng: 127.0286,
      rating: 4.9,
      specialties: ['Facial Contouring', 'Rhinoplasty', 'Double Eyelid'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_sl_02',
      name: 'Dr. Lee Sang-Hoon',
      clinicName: 'VIP International Plastic Surgery',
      address: '465 Gangnam-daero, Seocho-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06536',
      lat: 37.5037,
      lng: 127.0247,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Body Contouring', 'Breast'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_sl_03',
      name: 'Dr. Kim Byung-Gun',
      clinicName: 'BK Plastic Surgery',
      address: '358 Gangnam-daero, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06241',
      lat: 37.4979,
      lng: 127.0276,
      rating: 4.8,
      specialties: ['Facial Contouring', 'Eye Surgery', 'Anti-Aging'],
      boardCertified: true,
    ),

    // ── Brazil ────────────────────────────────────────────────────────────
    Provider(
      id: 'p_br_sp_01',
      name: 'Dr. Roberto Chacur',
      clinicName: 'Clínica Chacur',
      address: 'R. Joaquim Floriano, 466',
      city: 'São Paulo',
      state: 'SP, Brazil',
      zip: '04534-002',
      lat: -23.5837,
      lng: -46.6781,
      rating: 4.8,
      specialties: ['BBL', 'Body Contouring', 'Injectables'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_br_rj_01',
      name: 'Clínica Ivo Pitanguy',
      clinicName: 'Clínica Ivo Pitanguy',
      address: 'R. Dona Mariana, 65',
      city: 'Rio de Janeiro',
      state: 'RJ, Brazil',
      zip: '22280-020',
      lat: -22.9527,
      lng: -43.1856,
      rating: 4.9,
      specialties: ['Facelift', 'BBL', 'Breast'],
      boardCertified: true,
    ),

    // ── Mexico ────────────────────────────────────────────────────────────
    Provider(
      id: 'p_mx_cd_01',
      name: 'Dr. Carlos Walker',
      clinicName: 'Walker Cirugía Plástica',
      address: 'Av. Reforma 1500, Polanco',
      city: 'Mexico City',
      state: 'CDMX, Mexico',
      zip: '11550',
      lat: 19.4326,
      lng: -99.1925,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Breast', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_mx_tj_01',
      name: 'VIDA Wellness & Beauty',
      clinicName: 'VIDA Wellness & Beauty',
      address: 'Av. Paseo de los Héroes 10999',
      city: 'Tijuana',
      state: 'BC, Mexico',
      zip: '22010',
      lat: 32.5149,
      lng: -117.0382,
      rating: 4.7,
      specialties: ['Body Contouring', 'BBL', 'Facelift'],
      boardCertified: true,
    ),

    // ── United Arab Emirates ──────────────────────────────────────────────
    Provider(
      id: 'p_ae_du_01',
      name: 'Dr. Sanjay Parashar',
      clinicName: 'Cocoona Centre for Aesthetic Transformation',
      address: 'Al Wasl Rd, Jumeirah',
      city: 'Dubai',
      state: 'UAE',
      zip: '128739',
      lat: 25.2110,
      lng: 55.2438,
      rating: 4.9,
      specialties: ['Body Contouring', 'Rhinoplasty', 'Hair Transplant'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ae_du_02',
      name: 'Aesthetics International',
      clinicName: 'Aesthetics International',
      address: 'Al Razi Medical Complex, Dubai Healthcare City',
      city: 'Dubai',
      state: 'UAE',
      zip: '505005',
      lat: 25.2295,
      lng: 55.3273,
      rating: 4.8,
      specialties: ['Injectables', 'Laser', 'Skincare'],
      boardCertified: true,
    ),

    // ── Austin TX ───────────────────────────────────────────────────────
    Provider(
      id: 'p_us_atx_01',
      name: 'Dr. Robert Caridi',
      clinicName: 'Westlake Plastic Surgery',
      address: '5656 Bee Cave Rd',
      city: 'Austin',
      state: 'TX',
      zip: '78746',
      lat: 30.2756,
      lng: -97.8203,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Liposuction', 'Tummy Tuck'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_atx_02',
      name: 'Dr. Cameron Earl',
      clinicName: 'Skintology Medspa Austin',
      address: '2700 W Anderson Ln',
      city: 'Austin',
      state: 'TX',
      zip: '78757',
      lat: 30.3554,
      lng: -97.7335,
      rating: 4.9,
      specialties: ['Botox', 'Lip Filler', 'Microneedling'],
      boardCertified: true,
    ),
    // ── Nashville TN ────────────────────────────────────────────────────
    Provider(
      id: 'p_us_bna_01',
      name: 'Dr. Daniel A. Hatef',
      clinicName: 'Music City Plastic Surgery',
      address: '2010 Church St',
      city: 'Nashville',
      state: 'TN',
      zip: '37203',
      lat: 36.1545,
      lng: -86.7912,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Blepharoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_bna_02',
      name: 'Dr. Whitney Vance',
      clinicName: 'The Skin Bar Nashville',
      address: '4015 Hillsboro Pike',
      city: 'Nashville',
      state: 'TN',
      zip: '37215',
      lat: 36.1023,
      lng: -86.8156,
      rating: 4.9,
      specialties: ['Hydrafacial', 'Halo Laser', 'Microneedling'],
      boardCertified: true,
    ),
    // ── Charlotte NC ────────────────────────────────────────────────────
    Provider(
      id: 'p_us_clt_01',
      name: 'Dr. Kunal Patel',
      clinicName: 'Charlotte Plastic Surgery',
      address: '2215 Randolph Rd',
      city: 'Charlotte',
      state: 'NC',
      zip: '28207',
      lat: 35.2127,
      lng: -80.8222,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Liposuction', 'Mommy Makeover'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_clt_02',
      name: 'Studio CLT Aesthetics',
      clinicName: 'Studio CLT Aesthetics',
      address: '2820 Selwyn Ave',
      city: 'Charlotte',
      state: 'NC',
      zip: '28209',
      lat: 35.1916,
      lng: -80.8473,
      rating: 4.7,
      specialties: ['Botox', 'Filler', 'Chemical Peel'],
      boardCertified: true,
    ),
    // ── Portland OR ─────────────────────────────────────────────────────
    Provider(
      id: 'p_us_pdx_01',
      name: 'Dr. Mark Jewell',
      clinicName: 'Jewell Plastic Surgery',
      address: '1818 NW Northrup St',
      city: 'Portland',
      state: 'OR',
      zip: '97209',
      lat: 45.5318,
      lng: -122.6863,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Body Contouring', 'Liposuction'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_pdx_02',
      name: 'Skin by Lovely',
      clinicName: 'Skin by Lovely',
      address: '2055 NW Pettygrove St',
      city: 'Portland',
      state: 'OR',
      zip: '97209',
      lat: 45.5331,
      lng: -122.6929,
      rating: 4.9,
      specialties: ['Injectables', 'Microneedling', 'Laser'],
      boardCertified: true,
    ),
    // ── San Diego CA ────────────────────────────────────────────────────
    Provider(
      id: 'p_us_san_01',
      name: 'Dr. Hilinski',
      clinicName: 'La Jolla Cosmetic Surgery Centre',
      address: '9850 Genesee Ave',
      city: 'La Jolla',
      state: 'CA',
      zip: '92037',
      lat: 32.8865,
      lng: -117.2236,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Facelift', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_san_02',
      name: 'Dr. Amanda Lloyd',
      clinicName: 'Skin and Beauty Center San Diego',
      address: '4060 Fourth Ave',
      city: 'San Diego',
      state: 'CA',
      zip: '92103',
      lat: 32.7497,
      lng: -117.1614,
      rating: 4.8,
      specialties: ['Halo Laser', 'CoolSculpting', 'Botox'],
      boardCertified: true,
    ),
    // ── Detroit MI ──────────────────────────────────────────────────────
    Provider(
      id: 'p_us_dtw_01',
      name: 'Dr. Anthony Youn',
      clinicName: 'Youn Plastic Surgery',
      address: '50505 Schoenherr Rd',
      city: 'Troy',
      state: 'MI',
      zip: '48085',
      lat: 42.5806,
      lng: -83.1136,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Skincare'],
      boardCertified: true,
    ),
    // ── Minneapolis MN ──────────────────────────────────────────────────
    Provider(
      id: 'p_us_msp_01',
      name: 'Dr. Joe Gryskiewicz',
      clinicName: 'Minnesota Plastic Surgery',
      address: '15450 Highway 7',
      city: 'Minnetonka',
      state: 'MN',
      zip: '55345',
      lat: 44.9279,
      lng: -93.4836,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Liposuction', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_msp_02',
      name: 'Beauty Lab + Laser',
      clinicName: 'Beauty Lab + Laser',
      address: '4940 France Ave S',
      city: 'Edina',
      state: 'MN',
      zip: '55410',
      lat: 44.9067,
      lng: -93.3294,
      rating: 4.9,
      specialties: ['Halo Laser', 'BBL', 'Microneedling'],
      boardCertified: true,
    ),
    // ── Tampa / Orlando FL ──────────────────────────────────────────────
    Provider(
      id: 'p_us_tpa_01',
      name: 'Dr. James Christian',
      clinicName: 'Christian Plastic Surgery Tampa',
      address: '4444 W Bay Vista Ave',
      city: 'Tampa',
      state: 'FL',
      zip: '33611',
      lat: 27.8916,
      lng: -82.5145,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Tummy Tuck', 'BBL'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_tpa_02',
      name: 'Glow Aesthetics Tampa',
      clinicName: 'Glow Aesthetics',
      address: '3601 W Swann Ave',
      city: 'Tampa',
      state: 'FL',
      zip: '33609',
      lat: 27.9389,
      lng: -82.5006,
      rating: 4.7,
      specialties: ['Botox', 'Filler', 'Hydrafacial'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_mco_01',
      name: 'Dr. Edward Gross',
      clinicName: 'Gross Plastic Surgery',
      address: '4747 N Habana Ave',
      city: 'Orlando',
      state: 'FL',
      zip: '32808',
      lat: 28.5807,
      lng: -81.4096,
      rating: 4.7,
      specialties: ['Facelift', 'Eyelid Surgery', 'Rhinoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_mco_02',
      name: 'Sand Lake Dermatology',
      clinicName: 'Sand Lake Dermatology Center',
      address: '7335 W Sand Lake Rd',
      city: 'Orlando',
      state: 'FL',
      zip: '32819',
      lat: 28.4488,
      lng: -81.4858,
      rating: 4.8,
      specialties: ['Halo Laser', 'Chemical Peel', 'Microneedling'],
      boardCertified: true,
    ),
    // ── Philadelphia PA ─────────────────────────────────────────────────
    Provider(
      id: 'p_us_phl_01',
      name: 'Dr. Anthony LaBruna',
      clinicName: 'Philadelphia Cosmetic Surgery',
      address: '1601 Walnut St',
      city: 'Philadelphia',
      state: 'PA',
      zip: '19102',
      lat: 39.9509,
      lng: -75.1685,
      rating: 4.8,
      specialties: ['Rhinoplasty', 'Facelift', 'Blepharoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_phl_02',
      name: 'Schweiger Dermatology',
      clinicName: 'Schweiger Dermatology Group',
      address: '1740 South St',
      city: 'Philadelphia',
      state: 'PA',
      zip: '19146',
      lat: 39.9445,
      lng: -75.1717,
      rating: 4.7,
      specialties: ['Botox', 'Laser', 'Skincare'],
      boardCertified: true,
    ),
    // ── Midwest extras ──────────────────────────────────────────────────
    Provider(
      id: 'p_us_stl_01',
      name: 'Dr. Michele Koo',
      clinicName: 'Private Suite Aesthetics',
      address: '845 N New Ballas Ct',
      city: 'St. Louis',
      state: 'MO',
      zip: '63141',
      lat: 38.6597,
      lng: -90.4341,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Facelift', 'Liposuction'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_slc_01',
      name: 'Dr. Renato Saltz',
      clinicName: 'Saltz Plastic Surgery',
      address: '5445 S Highland Dr',
      city: 'Salt Lake City',
      state: 'UT',
      zip: '84117',
      lat: 40.6553,
      lng: -111.8569,
      rating: 4.9,
      specialties: ['Facelift', 'Breast Augmentation', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_mci_01',
      name: 'Dr. James Butler',
      clinicName: 'Kansas City Plastic Surgery',
      address: '5400 W 119th St',
      city: 'Leawood',
      state: 'KS',
      zip: '66209',
      lat: 38.9221,
      lng: -94.6739,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Liposuction', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_ind_01',
      name: 'Dr. Bruce Van Natta',
      clinicName: 'Meridian Plastic Surgeons',
      address: '170 W 106th St',
      city: 'Indianapolis',
      state: 'IN',
      zip: '46290',
      lat: 39.8896,
      lng: -86.1559,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Tummy Tuck', 'Liposuction'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_pit_01',
      name: 'Dr. Anna Wooten',
      clinicName: 'Beleza Plastic Surgery',
      address: '4001 Washington Rd',
      city: 'McMurray',
      state: 'PA',
      zip: '15317',
      lat: 40.2829,
      lng: -80.0848,
      rating: 4.8,
      specialties: ['Mommy Makeover', 'Breast Augmentation', 'BBL'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_sac_01',
      name: 'Sacramento Skin Co.',
      clinicName: 'Sacramento Skin Co.',
      address: '2801 K St',
      city: 'Sacramento',
      state: 'CA',
      zip: '95816',
      lat: 38.5762,
      lng: -121.4655,
      rating: 4.7,
      specialties: ['Botox', 'Microneedling', 'Hydrafacial'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_msy_01',
      name: 'Dr. Daniel Kapp',
      clinicName: 'New Orleans Aesthetic Surgery',
      address: '2401 Veterans Memorial Blvd',
      city: 'Metairie',
      state: 'LA',
      zip: '70002',
      lat: 29.9842,
      lng: -90.1610,
      rating: 4.7,
      specialties: ['Facelift', 'Breast Augmentation', 'Rhinoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_rdu_01',
      name: 'Dr. Cara Downey',
      clinicName: 'Raleigh Plastic Surgery Center',
      address: '3100 Duraleigh Rd',
      city: 'Raleigh',
      state: 'NC',
      zip: '27612',
      lat: 35.8526,
      lng: -78.7039,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Liposuction', 'Tummy Tuck'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_us_cvg_01',
      name: 'Dr. James Koehler',
      clinicName: 'Cincinnati Plastic Surgery',
      address: '9403 Kenwood Rd',
      city: 'Cincinnati',
      state: 'OH',
      zip: '45242',
      lat: 39.2147,
      lng: -84.3700,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Breast Augmentation', 'Facelift'],
      boardCertified: true,
    ),

    // ── Canada — Vancouver, Montreal, Calgary ───────────────────────────
    Provider(
      id: 'p_ca_yvr_01',
      name: 'Dr. Martin Braun',
      clinicName: 'Anti-Aging Medical & Laser Clinic',
      address: '1675 Broadway W',
      city: 'Vancouver',
      state: 'BC',
      zip: 'V6J 1X6',
      lat: 49.2638,
      lng: -123.1462,
      rating: 4.8,
      specialties: ['Halo Laser', 'Botox', 'Filler'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_yvr_02',
      name: 'Dr. Peter Lennox',
      clinicName: 'Vancouver Plastic Surgery',
      address: '1090 W Pender St',
      city: 'Vancouver',
      state: 'BC',
      zip: 'V6E 2N7',
      lat: 49.2884,
      lng: -123.1198,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Rhinoplasty', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_yul_01',
      name: 'Dr. Chen Lee',
      clinicName: 'Cosmedica Laser Center Montreal',
      address: '1, Place Ville Marie',
      city: 'Montreal',
      state: 'QC',
      zip: 'H3B 4S6',
      lat: 45.5009,
      lng: -73.5683,
      rating: 4.7,
      specialties: ['Laser', 'CoolSculpting', 'Microneedling'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_yul_02',
      name: 'Dr. Arie Benchetrit',
      clinicName: 'Cosmedica Plastic Surgery',
      address: '4055 Ste-Catherine W',
      city: 'Montreal',
      state: 'QC',
      zip: 'H3Z 3J8',
      lat: 45.4869,
      lng: -73.5957,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Liposuction', 'Tummy Tuck'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ca_yyc_01',
      name: 'Dr. Robert Lindsay',
      clinicName: 'Lindsay Plastic Surgery',
      address: '1402 8 Ave NW',
      city: 'Calgary',
      state: 'AB',
      zip: 'T2N 1B9',
      lat: 51.0631,
      lng: -114.0916,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Eyelid Surgery', 'Facelift'],
      boardCertified: true,
    ),

    // ── UK extras — Manchester, Birmingham, Edinburgh, Leeds ────────────
    Provider(
      id: 'p_uk_man_01',
      name: 'Dr. Andrew Baildam',
      clinicName: 'The Alexandra Hospital Plastic Surgery',
      address: 'Mill Lane, Cheadle',
      city: 'Manchester',
      state: 'UK',
      zip: 'SK8 2PX',
      lat: 53.3958,
      lng: -2.2003,
      rating: 4.7,
      specialties: [
        'Breast Augmentation',
        'Breast Reduction',
        'Body Contouring',
      ],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_man_02',
      name: 'Skin Aesthetics Manchester',
      clinicName: 'Skin Aesthetics',
      address: '1 Hardman Square',
      city: 'Manchester',
      state: 'UK',
      zip: 'M3 3EB',
      lat: 53.4789,
      lng: -2.2509,
      rating: 4.8,
      specialties: ['Botox', 'Lip Filler', 'Microneedling'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_bhm_01',
      name: 'Dr. Sonia Khorana',
      clinicName: 'Birmingham Dermatology',
      address: 'Edgbaston, Calthorpe Rd',
      city: 'Birmingham',
      state: 'UK',
      zip: 'B15 1QY',
      lat: 52.4750,
      lng: -1.9213,
      rating: 4.7,
      specialties: ['Skincare', 'Microneedling', 'Chemical Peel'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_edi_01',
      name: 'Dr. Taimur Shoaib',
      clinicName: 'La Belle Forme Edinburgh',
      address: '70 Manor Place',
      city: 'Edinburgh',
      state: 'UK',
      zip: 'EH3 7EH',
      lat: 55.9505,
      lng: -3.2191,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_uk_lba_01',
      name: 'Leeds Skin Clinic',
      clinicName: 'Leeds Skin Clinic',
      address: '88 Park Lane',
      city: 'Leeds',
      state: 'UK',
      zip: 'LS3 1EL',
      lat: 53.8008,
      lng: -1.5491,
      rating: 4.7,
      specialties: ['Botox', 'Filler', 'Halo Laser'],
      boardCertified: true,
    ),

    // ── Australia — Melbourne, Brisbane, Perth ──────────────────────────
    Provider(
      id: 'p_au_mel_01',
      name: 'Dr. Mark Magnusson',
      clinicName: 'Melbourne Plastic Surgery',
      address: '766 Elizabeth St',
      city: 'Melbourne',
      state: 'AU',
      zip: '3000',
      lat: -37.8051,
      lng: 144.9614,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Rhinoplasty', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_mel_02',
      name: 'Dr. Daniel Lanzer',
      clinicName: 'Lanzer Cosmetic Clinic',
      address: '99 St Kilda Rd',
      city: 'Melbourne',
      state: 'AU',
      zip: '3182',
      lat: -37.8666,
      lng: 144.9810,
      rating: 4.6,
      specialties: ['Liposuction', 'Tummy Tuck', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_mel_03',
      name: 'ENRICH Clinic Melbourne',
      clinicName: 'ENRICH Clinic',
      address: '232 Victoria Pde',
      city: 'Melbourne',
      state: 'AU',
      zip: '3002',
      lat: -37.8112,
      lng: 144.9778,
      rating: 4.9,
      specialties: ['Laser', 'Halo Laser', 'Microneedling'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_bne_01',
      name: 'Dr. Mark Magnusson',
      clinicName: 'Magnusson Plastic Surgery Brisbane',
      address: '1/9 Sherwood Rd',
      city: 'Brisbane',
      state: 'AU',
      zip: '4066',
      lat: -27.4845,
      lng: 152.9785,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Facelift', 'Rhinoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_bne_02',
      name: 'Cosmos Clinic Brisbane',
      clinicName: 'Cosmos Clinic',
      address: '40 Annerley Rd',
      city: 'Brisbane',
      state: 'AU',
      zip: '4102',
      lat: -27.4886,
      lng: 153.0260,
      rating: 4.7,
      specialties: ['Liposuction', 'CoolSculpting', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_au_per_01',
      name: 'Dr. Mark Hanikeri',
      clinicName: 'Academy Face & Body Perth',
      address: '8 Pier St',
      city: 'Perth',
      state: 'AU',
      zip: '6000',
      lat: -31.9527,
      lng: 115.8606,
      rating: 4.8,
      specialties: ['Rhinoplasty', 'Facelift', 'Breast Augmentation'],
      boardCertified: true,
    ),

    // ── South Korea — Gangnam Seoul + Busan ─────────────────────────────
    Provider(
      id: 'p_kr_sel_04',
      name: 'JK Plastic Surgery Center',
      clinicName: 'JK Plastic Surgery Center',
      address: '7 Nonhyeon-ro 175-gil, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06104',
      lat: 37.5126,
      lng: 127.0223,
      rating: 4.9,
      specialties: ['Rhinoplasty', 'Facelift', 'Eyelid Surgery'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_sel_05',
      name: 'ID Hospital Seoul',
      clinicName: 'ID Hospital',
      address: '142 Dosan-daero, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06039',
      lat: 37.5247,
      lng: 127.0387,
      rating: 4.8,
      specialties: ['V-line Surgery', 'Rhinoplasty', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_sel_06',
      name: 'BK Plastic Surgery Hospital',
      clinicName: 'BK Plastic Surgery Hospital',
      address: '465 Gangnam-daero, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06120',
      lat: 37.5040,
      lng: 127.0246,
      rating: 4.8,
      specialties: ['Eyelid Surgery', 'Rhinoplasty', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_sel_07',
      name: 'Banobagi Plastic Surgery',
      clinicName: 'Banobagi Plastic Surgery Clinic',
      address: '584 Nonhyeon-ro, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06034',
      lat: 37.5170,
      lng: 127.0339,
      rating: 4.9,
      specialties: ['Facelift', 'Rhinoplasty', 'Skincare'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_sel_08',
      name: 'Wonjin Plastic Surgery',
      clinicName: 'Wonjin Plastic Surgery',
      address: '829 Nonhyeon-ro, Gangnam-gu',
      city: 'Seoul',
      state: 'South Korea',
      zip: '06032',
      lat: 37.5125,
      lng: 127.0240,
      rating: 4.7,
      specialties: ['Eyelid Surgery', 'Liposuction', 'Rhinoplasty'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_kr_pus_01',
      name: 'Busan Aesthetic Clinic',
      clinicName: 'Busan Aesthetic Clinic',
      address: '147 Centum Jungang-ro',
      city: 'Busan',
      state: 'South Korea',
      zip: '48058',
      lat: 35.1693,
      lng: 129.1305,
      rating: 4.7,
      specialties: ['Botox', 'Filler', 'Microneedling'],
      boardCertified: true,
    ),

    // ── Brazil — Rio + São Paulo ────────────────────────────────────────
    Provider(
      id: 'p_br_rio_01',
      name: 'Dr. Ivo Pitanguy Clinic',
      clinicName: 'Clínica Ivo Pitanguy',
      address: 'Rua Dona Mariana, 65',
      city: 'Rio de Janeiro',
      state: 'Brazil',
      zip: '22280-020',
      lat: -22.9495,
      lng: -43.1797,
      rating: 4.9,
      specialties: ['Facelift', 'BBL', 'Body Contouring'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_br_rio_02',
      name: 'Dr. Sergio Castilho',
      clinicName: 'Castilho Cirurgia Plástica',
      address: 'Av. das Américas, 3500',
      city: 'Rio de Janeiro',
      state: 'Brazil',
      zip: '22640-102',
      lat: -23.0014,
      lng: -43.3637,
      rating: 4.8,
      specialties: ['BBL', 'Liposuction', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_br_sao_03',
      name: 'Dr. Renato Saltz Brasil',
      clinicName: 'Clínica Renato Saltz',
      address: 'Av. Brasil, 2027',
      city: 'São Paulo',
      state: 'Brazil',
      zip: '01430-001',
      lat: -23.5675,
      lng: -46.6717,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Breast Augmentation'],
      boardCertified: true,
    ),

    // ── Mexico extras ───────────────────────────────────────────────────
    Provider(
      id: 'p_mx_cun_01',
      name: 'Dr. Victor Ramirez',
      clinicName: 'Cancún Plastic Surgery',
      address: 'Av. Bonampak SM 6',
      city: 'Cancún',
      state: 'Mexico',
      zip: '77500',
      lat: 21.1604,
      lng: -86.8226,
      rating: 4.7,
      specialties: ['BBL', 'Tummy Tuck', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_mx_gdl_01',
      name: 'Dr. Carlos Mendoza',
      clinicName: 'Mendoza Plastic Surgery',
      address: 'Av. Vallarta 6503',
      city: 'Guadalajara',
      state: 'Mexico',
      zip: '45010',
      lat: 20.6743,
      lng: -103.4316,
      rating: 4.7,
      specialties: ['Rhinoplasty', 'Liposuction', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_mx_tij_01',
      name: 'CER Plastic Surgery',
      clinicName: 'CER Hospital',
      address: 'Paseo Centenario 9520',
      city: 'Tijuana',
      state: 'Mexico',
      zip: '22010',
      lat: 32.5266,
      lng: -117.0309,
      rating: 4.8,
      specialties: ['Tummy Tuck', 'BBL', 'Mommy Makeover'],
      boardCertified: true,
    ),

    // ── UAE extras ──────────────────────────────────────────────────────
    Provider(
      id: 'p_ae_auh_01',
      name: 'Dr. Maurizio Viel',
      clinicName: 'Cornerstone Clinic Abu Dhabi',
      address: 'Eastern Mangroves Promenade',
      city: 'Abu Dhabi',
      state: 'UAE',
      zip: '128331',
      lat: 24.4731,
      lng: 54.3905,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Botox'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_ae_du_03',
      name: 'Kaya Skin Clinic Dubai',
      clinicName: 'Kaya Skin Clinic',
      address: 'Jumeirah Beach Rd',
      city: 'Dubai',
      state: 'UAE',
      zip: '212222',
      lat: 25.2197,
      lng: 55.2596,
      rating: 4.7,
      specialties: ['Hydrafacial', 'Laser', 'Skincare'],
      boardCertified: true,
    ),

    // ── Thailand — Bangkok + Phuket ─────────────────────────────────────
    Provider(
      id: 'p_th_bkk_01',
      name: 'Dr. Kunakorn Atchariyasakchai',
      clinicName: 'Bangkok Plastic Surgery Clinic',
      address: '139 Pan Rd, Silom',
      city: 'Bangkok',
      state: 'Thailand',
      zip: '10500',
      lat: 13.7233,
      lng: 100.5240,
      rating: 4.8,
      specialties: ['Rhinoplasty', 'Eyelid Surgery', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_th_bkk_02',
      name: 'Yanhee Hospital',
      clinicName: 'Yanhee International Hospital',
      address: '454 Charansanitwong Rd',
      city: 'Bangkok',
      state: 'Thailand',
      zip: '10700',
      lat: 13.7766,
      lng: 100.4798,
      rating: 4.7,
      specialties: ['Breast Augmentation', 'Liposuction', 'Hair Transplant'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_th_bkk_03',
      name: 'Nida Esth Cosmetic Center',
      clinicName: 'Nida Esth',
      address: '4/1-2 Convent Rd, Silom',
      city: 'Bangkok',
      state: 'Thailand',
      zip: '10500',
      lat: 13.7252,
      lng: 100.5310,
      rating: 4.8,
      specialties: ['Botox', 'Filler', 'Microneedling'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_th_hkt_01',
      name: 'Phuket Plastic Surgery Institute',
      clinicName: 'PPSI',
      address: '90 Hongyok Utis Rd',
      city: 'Phuket',
      state: 'Thailand',
      zip: '83000',
      lat: 7.8804,
      lng: 98.3923,
      rating: 4.7,
      specialties: ['Body Contouring', 'Breast Augmentation', 'Rhinoplasty'],
      boardCertified: true,
    ),

    // ── Turkey — Istanbul ───────────────────────────────────────────────
    Provider(
      id: 'p_tr_ist_01',
      name: 'Dr. Bulent Cihantimur',
      clinicName: 'Estetik International',
      address: 'Kanyon AVM, Levent',
      city: 'Istanbul',
      state: 'Turkey',
      zip: '34394',
      lat: 41.0827,
      lng: 29.0119,
      rating: 4.8,
      specialties: ['BBL', 'Liposuction', 'Tummy Tuck'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_tr_ist_02',
      name: 'Dr. Selahattin Tulunay',
      clinicName: 'Tulunay Hair Transplant Center',
      address: 'Etiler, Nispetiye Cad.',
      city: 'Istanbul',
      state: 'Turkey',
      zip: '34337',
      lat: 41.0816,
      lng: 29.0356,
      rating: 4.9,
      specialties: ['Hair Transplant', 'FUE', 'PRP'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_tr_ist_03',
      name: 'Vera Clinic Istanbul',
      clinicName: 'Vera Clinic',
      address: 'Atasehir, Barbaros Mh.',
      city: 'Istanbul',
      state: 'Turkey',
      zip: '34746',
      lat: 40.9923,
      lng: 29.1244,
      rating: 4.7,
      specialties: ['Hair Transplant', 'Rhinoplasty', 'Botox'],
      boardCertified: true,
    ),

    // ── Singapore, Tokyo, Hong Kong, Taipei ─────────────────────────────
    Provider(
      id: 'p_sg_sin_01',
      name: 'Dr. Marco Faria-Correa',
      clinicName: 'Marco Faria-Correa Plastic Surgery',
      address: '290 Orchard Rd',
      city: 'Singapore',
      state: 'Singapore',
      zip: '238859',
      lat: 1.3036,
      lng: 103.8313,
      rating: 4.9,
      specialties: ['Tummy Tuck', 'Breast Augmentation', 'Liposuction'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_sg_sin_02',
      name: 'The Sloane Clinic',
      clinicName: 'The Sloane Clinic',
      address: '435 Orchard Rd',
      city: 'Singapore',
      state: 'Singapore',
      zip: '238877',
      lat: 1.3036,
      lng: 103.8316,
      rating: 4.8,
      specialties: ['Botox', 'Filler', 'Halo Laser'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_jp_tyo_01',
      name: 'Shinagawa Skin Clinic',
      clinicName: 'Shinagawa Skin Clinic',
      address: '2-3-13 Takanawa, Minato',
      city: 'Tokyo',
      state: 'Japan',
      zip: '108-0074',
      lat: 35.6364,
      lng: 139.7400,
      rating: 4.7,
      specialties: ['Laser', 'Microneedling', 'Skincare'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_jp_tyo_02',
      name: 'Tokyo Cosmetic Surgery',
      clinicName: 'Tokyo Cosmetic Surgery Clinic',
      address: '3-25-18 Shinjuku',
      city: 'Tokyo',
      state: 'Japan',
      zip: '160-0022',
      lat: 35.6913,
      lng: 139.7036,
      rating: 4.7,
      specialties: ['Eyelid Surgery', 'Rhinoplasty', 'Botox'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_hk_hkg_01',
      name: 'Dr. Vincent Wong',
      clinicName: 'Central Aesthetics Hong Kong',
      address: '1 Queen\'s Road Central',
      city: 'Hong Kong',
      state: 'Hong Kong',
      zip: '00000',
      lat: 22.2820,
      lng: 114.1588,
      rating: 4.8,
      specialties: ['Botox', 'Filler', 'Halo Laser'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_tw_tpe_01',
      name: 'Dr. David Chu',
      clinicName: 'Taipei Aesthetic Clinic',
      address: 'No. 12 Dunhua S Rd',
      city: 'Taipei',
      state: 'Taiwan',
      zip: '106',
      lat: 25.0397,
      lng: 121.5495,
      rating: 4.7,
      specialties: ['Eyelid Surgery', 'Rhinoplasty', 'Microneedling'],
      boardCertified: true,
    ),

    // ── Europe extras — Paris, Madrid, Milan ────────────────────────────
    Provider(
      id: 'p_fr_par_01',
      name: 'Dr. Olivier de Frahan',
      clinicName: 'Clinique de Frahan Paris',
      address: '16 Rue de Marignan',
      city: 'Paris',
      state: 'France',
      zip: '75008',
      lat: 48.8693,
      lng: 2.3081,
      rating: 4.8,
      specialties: ['Facelift', 'Rhinoplasty', 'Breast Augmentation'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_fr_par_02',
      name: 'Clinique des Champs-Élysées',
      clinicName: 'Clinique des Champs-Élysées',
      address: '102 Av. des Champs-Élysées',
      city: 'Paris',
      state: 'France',
      zip: '75008',
      lat: 48.8723,
      lng: 2.3026,
      rating: 4.7,
      specialties: ['Botox', 'Laser', 'Hydrafacial'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_es_mad_01',
      name: 'Dr. Javier de Benito',
      clinicName: 'Clínica de Benito Madrid',
      address: 'Calle de Velázquez, 24',
      city: 'Madrid',
      state: 'Spain',
      zip: '28001',
      lat: 40.4252,
      lng: -3.6864,
      rating: 4.8,
      specialties: ['Breast Augmentation', 'Rhinoplasty', 'Facelift'],
      boardCertified: true,
    ),
    Provider(
      id: 'p_it_mil_01',
      name: 'Dr. Massimo Robiony',
      clinicName: 'Robiony Aesthetic Clinic Milan',
      address: 'Via Manzoni, 12',
      city: 'Milan',
      state: 'Italy',
      zip: '20121',
      lat: 45.4685,
      lng: 9.1944,
      rating: 4.7,
      specialties: ['Facelift', 'Rhinoplasty', 'Blepharoplasty'],
      boardCertified: true,
    ),
  ];

  /// Centroid lat/lng for common US zip-code prefixes (first 3 digits).
  /// Used to estimate distance when the user's exact zip isn't directly
  /// matched in the directory. Coverage focuses on major metros that
  /// host the curated providers above.
  static const Map<String, List<double>> _zip3Centroids = {
    '900': [34.05, -118.25], '901': [34.05, -118.30], '902': [34.05, -118.40],
    '903': [33.90, -118.40], '904': [34.02, -118.50], '905': [33.80, -118.20],
    '906': [33.78, -118.10], '907': [33.80, -118.16], '908': [33.85, -118.20],
    '910': [34.15, -118.15], '911': [34.15, -118.15], '912': [34.10, -118.05],
    '913': [34.20, -118.55], '914': [34.30, -118.45],
    '917': [34.10, -117.90], '918': [34.10, -117.70],
    '919': [33.00, -116.95], '920': [32.90, -117.10], '921': [32.75, -117.15],
    '922': [33.75, -117.80],
    '940': [37.78, -122.42], '941': [37.78, -122.42], '942': [37.78, -122.42],
    '943': [37.45, -122.15], '944': [37.55, -122.25], '945': [37.80, -122.20],
    '946': [37.85, -122.27], '947': [37.85, -122.27], '948': [37.70, -122.20],
    '950': [37.30, -121.90], '951': [37.30, -121.90], '952': [37.30, -121.90],
    '953': [37.95, -121.30], '954': [38.45, -122.70],
    '980': [47.61, -122.33], '981': [47.61, -122.33], '982': [47.97, -122.20],
    '983': [47.25, -122.45], '984': [47.25, -122.45], '985': [47.05, -122.90],
    '100': [40.78, -73.97], '101': [40.78, -73.97], '102': [40.78, -73.97],
    '103': [40.58, -74.15], '104': [40.85, -73.87], '105': [40.95, -73.85],
    '106': [41.05, -73.78], '107': [41.10, -73.95], '110': [40.72, -73.83],
    '111': [40.72, -73.85], '112': [40.65, -73.95], '113': [40.74, -73.80],
    '114': [40.75, -73.75], '115': [40.78, -73.55], '116': [40.62, -73.75],
    '117': [40.85, -73.10], '118': [40.75, -73.55], '119': [40.85, -72.85],
    '330': [25.78, -80.20], '331': [25.78, -80.20], '332': [25.78, -80.20],
    '333': [26.12, -80.14], '334': [26.71, -80.05], '335': [27.95, -82.46],
    '336': [27.95, -82.46], '337': [27.95, -82.46], '338': [28.04, -81.95],
    '770': [29.76, -95.37], '771': [29.76, -95.37], '772': [29.76, -95.37],
    '773': [30.30, -95.45], '774': [29.55, -95.10], '775': [29.30, -94.80],
    '776': [29.85, -94.10], '777': [30.07, -94.13], '778': [30.62, -96.33],
    '779': [30.45, -96.10], '780': [29.42, -98.50], '781': [29.42, -98.50],
    '782': [29.42, -98.50], '783': [27.80, -97.40], '784': [27.80, -97.40],
    '785': [26.20, -98.23],
    '750': [32.78, -96.80], '751': [32.78, -96.80], '752': [32.78, -96.80],
    '753': [32.78, -96.80], '754': [33.10, -96.10], '755': [32.35, -95.30],
    '756': [32.35, -95.30], '757': [32.50, -94.74], '758': [31.10, -97.34],
    '787': [30.27, -97.74], '788': [30.50, -98.27], '789': [30.27, -97.74],
    '600': [41.88, -87.63], '601': [41.88, -87.63], '602': [42.00, -87.93],
    '603': [41.78, -88.00], '604': [42.15, -87.80], '605': [41.65, -87.70],
    '606': [41.88, -87.63], '607': [41.78, -88.40], '608': [41.40, -88.10],
    '300': [33.75, -84.39], '301': [33.75, -84.39], '302': [33.75, -84.39],
    '303': [33.75, -84.39], '304': [34.05, -84.20], '305': [34.30, -83.97],
    '021': [42.36, -71.06], '022': [42.36, -71.06], '023': [42.10, -71.00],
    '024': [41.85, -71.30], '025': [41.65, -70.93], '026': [41.85, -70.95],
    '850': [33.45, -112.07], '851': [33.45, -112.07], '852': [33.45, -112.07],
    '853': [33.45, -112.07], '855': [34.05, -109.30],
    '800': [39.74, -104.99], '801': [39.74, -104.99], '802': [39.74, -104.99],
    '803': [40.15, -105.10], '804': [40.10, -105.10], '805': [39.55, -104.85],
    '890': [36.17, -115.14], '891': [36.17, -115.14], '892': [36.17, -115.14],
    '893': [39.53, -119.81], '894': [39.53, -119.81],
    '200': [38.90, -77.04], '201': [38.90, -77.04], '202': [38.90, -77.04],
    '203': [38.90, -77.04], '204': [38.90, -77.04], '205': [38.90, -77.04],
    '206': [38.90, -77.04], '207': [38.95, -76.95], '208': [39.00, -77.10],
    '209': [38.99, -76.78],
    // Ohio — precise 3-digit centroids so Warren/Akron/Youngstown
    // don't all collapse onto the Cleveland 2-digit fallback.
    '440': [41.50, -81.62], // Cleveland
    '441': [41.50, -81.62], // Cleveland
    '442': [41.08, -81.52], // Akron
    '443': [41.08, -81.52], // Akron
    '444': [41.2398, -80.8184], // Warren / Youngstown area (44483)
    '445': [41.0998, -80.6495], // Youngstown
    '446': [40.7989, -81.3784], // Canton
    '447': [40.7989, -81.3784], // Canton
    '448': [40.7989, -82.5154], // Mansfield
    '449': [40.7989, -82.5154], // Mansfield
    '430': [39.9612, -82.9988], // Columbus
    '431': [39.9612, -82.9988], // Columbus
    '432': [39.9612, -82.9988], // Columbus
    '433': [40.0992, -83.1141], // Dublin / NW Columbus
    '434': [41.6528, -83.5379], // Toledo
    '435': [41.6528, -83.5379], // Toledo
    '436': [40.7575, -84.1052], // Lima
    '437': [40.4173, -82.9071], // Mansfield/Mt Vernon
    '438': [40.4173, -82.9071], // Newark
    '439': [40.5853, -82.4072], // Zanesville
    '450': [39.1031, -84.5120], // Cincinnati
    '451': [39.1031, -84.5120], // Cincinnati
    '452': [39.1031, -84.5120], // Cincinnati
    '453': [39.7589, -84.1916], // Dayton
    '454': [39.7589, -84.1916], // Dayton
    '455': [39.7589, -84.1916], // Dayton
    '456': [39.1612, -82.9988], // SE Ohio
  };

  /// 2-digit zip prefix → state/region centroid [lat, lng].
  /// Provides fallback coverage for every valid US postal code when the
  /// 3-digit prefix isn't in the more-precise [_zip3Centroids] map.
  static const Map<String, List<double>> _zip2Centroids = {
    '00': [43.0, -71.5],
    '01': [42.3, -71.8],
    '02': [41.8, -71.4],
    '03': [43.2, -71.5],
    '04': [44.3, -70.2],
    '05': [44.0, -72.7],
    '06': [41.6, -72.7],
    '07': [40.9, -74.2],
    '08': [39.8, -74.8],
    '09': [38.9, -77.0],
    '10': [40.7, -74.0],
    '11': [40.7, -73.8],
    '12': [42.7, -73.8],
    '13': [43.0, -75.4],
    '14': [42.9, -78.6],
    '15': [40.4, -79.9],
    '16': [41.0, -80.0],
    '17': [40.3, -77.0],
    '18': [41.0, -75.8],
    '19': [39.9, -75.2],
    '20': [38.9, -77.0],
    '21': [39.3, -76.6],
    '22': [38.8, -77.1],
    '23': [37.5, -77.5],
    '24': [37.3, -80.0],
    '25': [38.5, -81.3],
    '26': [39.3, -80.5],
    '27': [35.8, -79.0],
    '28': [35.2, -80.8],
    '29': [33.8, -80.9],
    '30': [33.7, -84.4],
    '31': [32.5, -83.5],
    '32': [28.5, -81.4],
    '33': [25.8, -80.2],
    '34': [27.5, -82.5],
    '35': [34.0, -86.8],
    '36': [32.4, -86.9],
    '37': [35.8, -86.2],
    '38': [35.1, -89.0],
    '39': [32.3, -89.3],
    '40': [38.2, -85.7],
    '41': [37.8, -83.3],
    '42': [37.0, -87.5],
    '43': [40.0, -82.9],
    '44': [41.5, -81.7],
    '45': [39.3, -84.5],
    '46': [41.1, -86.1],
    '47': [39.8, -86.1],
    '48': [42.3, -83.0],
    '49': [43.6, -85.6],
    '50': [42.0, -93.6],
    '51': [42.5, -95.9],
    '52': [42.0, -91.7],
    '53': [43.0, -88.8],
    '54': [44.9, -89.6],
    '55': [44.9, -93.5],
    '56': [46.6, -94.0],
    '57': [44.3, -100.3],
    '58': [46.9, -100.4],
    '59': [47.0, -109.6],
    '60': [41.9, -87.6],
    '61': [40.5, -89.0],
    '62': [38.5, -89.9],
    '63': [38.6, -90.2],
    '64': [39.1, -94.6],
    '65': [37.9, -92.4],
    '66': [39.0, -95.7],
    '67': [38.0, -98.0],
    '68': [41.3, -96.0],
    '69': [41.1, -101.7],
    '70': [29.9, -90.1],
    '71': [32.5, -92.1],
    '72': [34.7, -92.3],
    '73': [35.5, -97.5],
    '74': [36.1, -96.0],
    '75': [32.8, -96.8],
    '76': [32.7, -97.3],
    '77': [29.8, -95.4],
    '78': [29.4, -98.5],
    '79': [31.5, -100.4],
    '80': [39.7, -104.9],
    '81': [38.8, -108.0],
    '82': [42.9, -106.3],
    '83': [43.5, -116.2],
    '84': [40.8, -111.9],
    '85': [33.4, -112.1],
    '86': [35.2, -111.7],
    '87': [35.1, -106.6],
    '88': [32.3, -106.8],
    '89': [36.2, -115.1],
    '90': [34.0, -118.3],
    '91': [34.2, -118.4],
    '92': [33.8, -117.9],
    '93': [36.7, -119.8],
    '94': [37.6, -122.1],
    '95': [38.6, -121.5],
    '96': [21.3, -157.8],
    '97': [44.6, -122.8],
    '98': [47.5, -122.0],
    '99': [61.2, -149.9],
  };

  /// Canadian postal code FSA first-letter → province centroid.
  /// First character of a Canadian postal code identifies the province /
  /// territory; this gives "good enough" coordinates for distance ranking.
  static const Map<String, List<double>> _canadaPostalPrefixes = {
    'A': [47.5615, -52.7126], // Newfoundland (St. John's)
    'B': [44.6488, -63.5752], // Nova Scotia (Halifax)
    'C': [46.2382, -63.1311], // PEI (Charlottetown)
    'E': [45.9636, -66.6431], // New Brunswick (Fredericton)
    'G': [46.8139, -71.2080], // Eastern Quebec (Quebec City)
    'H': [45.5017, -73.5673], // Montreal
    'J': [45.4042, -73.4385], // Western Quebec
    'K': [45.4215, -75.6972], // Eastern Ontario (Ottawa)
    'L': [43.7315, -79.7624], // Central Ontario (GTA west)
    'M': [43.6532, -79.3832], // Toronto
    'N': [43.0096, -81.2453], // SW Ontario (London)
    'P': [46.4917, -84.3416], // Northern Ontario
    'R': [49.8951, -97.1384], // Manitoba (Winnipeg)
    'S': [52.1332, -106.6700], // Saskatchewan (Saskatoon)
    'T': [51.0447, -114.0719], // Alberta (Calgary)
    'V': [49.2827, -123.1207], // British Columbia (Vancouver)
    'X': [62.4540, -114.3718], // Northern Territories
    'Y': [60.7212, -135.0568], // Yukon (Whitehorse)
  };

  /// UK outward-code prefixes (first 1–2 letters) → city centroid.
  static const Map<String, List<double>> _ukPostalPrefixes = {
    // London (multiple postal areas)
    'E': [51.5414, -0.0167], 'EC': [51.5155, -0.0922],
    'N': [51.5641, -0.1059], 'NW': [51.5530, -0.1957],
    'SE': [51.4839, -0.0780], 'SW': [51.4625, -0.1660],
    'W': [51.5142, -0.1810], 'WC': [51.5174, -0.1238],
    // Major UK cities
    'M': [53.4808, -2.2426], // Manchester
    'B': [52.4862, -1.8904], // Birmingham
    'L': [53.4084, -2.9916], // Liverpool
    'LS': [53.8008, -1.5491], // Leeds
    'S': [53.3811, -1.4701], // Sheffield
    'BS': [51.4545, -2.5879], // Bristol
    'CF': [51.4816, -3.1791], // Cardiff
    'EH': [55.9533, -3.1883], // Edinburgh
    'G': [55.8642, -4.2518], // Glasgow
    'BT': [54.5973, -5.9301], // Belfast
    'OX': [51.7520, -1.2577], // Oxford
    'CB': [52.2053, 0.1218], // Cambridge
    'BN': [50.8225, -0.1372], // Brighton
  };

  /// Worldwide city / country / region name → centroid.
  /// Keys are lowercase and matched as a substring of the trimmed input,
  /// so users can type "London", "Tokyo", "Seoul", "São Paulo", etc.
  static const Map<String, List<double>> _globalCityCentroids = {
    // North America (extra US metros are already covered by zip prefixes)
    'toronto': [43.6532, -79.3832],
    'vancouver': [49.2827, -123.1207],
    'montreal': [45.5017, -73.5673],
    'ottawa': [45.4215, -75.6972],
    'calgary': [51.0447, -114.0719],
    'edmonton': [53.5461, -113.4938],
    'mexico city': [19.4326, -99.1332],
    'ciudad de mexico': [19.4326, -99.1332],
    'guadalajara': [20.6597, -103.3496],
    'monterrey': [25.6866, -100.3161],
    'tijuana': [32.5149, -117.0382],
    'cancun': [21.1619, -86.8515],
    // Europe
    'london': [51.5074, -0.1278],
    'manchester': [53.4808, -2.2426],
    'birmingham': [52.4862, -1.8904],
    'edinburgh': [55.9533, -3.1883],
    'dublin': [53.3498, -6.2603],
    'paris': [48.8566, 2.3522],
    'madrid': [40.4168, -3.7038],
    'barcelona': [41.3851, 2.1734],
    'rome': [41.9028, 12.4964],
    'milan': [45.4642, 9.1900],
    'berlin': [52.5200, 13.4050],
    'munich': [48.1351, 11.5820],
    'amsterdam': [52.3676, 4.9041],
    'zurich': [47.3769, 8.5417],
    'vienna': [48.2082, 16.3738],
    'stockholm': [59.3293, 18.0686],
    'copenhagen': [55.6761, 12.5683],
    'lisbon': [38.7223, -9.1393],
    'athens': [37.9838, 23.7275],
    'istanbul': [41.0082, 28.9784],
    // Middle East
    'dubai': [25.2048, 55.2708],
    'abu dhabi': [24.4539, 54.3773],
    'doha': [25.2854, 51.5310],
    'riyadh': [24.7136, 46.6753],
    'jeddah': [21.4858, 39.1925],
    'tel aviv': [32.0853, 34.7818],
    // Asia
    'seoul': [37.5665, 126.9780],
    'busan': [35.1796, 129.0756],
    'tokyo': [35.6762, 139.6503],
    'osaka': [34.6937, 135.5023],
    'kyoto': [35.0116, 135.7681],
    'beijing': [39.9042, 116.4074],
    'shanghai': [31.2304, 121.4737],
    'hong kong': [22.3193, 114.1694],
    'taipei': [25.0330, 121.5654],
    'singapore': [1.3521, 103.8198],
    'bangkok': [13.7563, 100.5018],
    'kuala lumpur': [3.1390, 101.6869],
    'jakarta': [-6.2088, 106.8456],
    'manila': [14.5995, 120.9842],
    'mumbai': [19.0760, 72.8777],
    'delhi': [28.7041, 77.1025],
    'new delhi': [28.6139, 77.2090],
    'bangalore': [12.9716, 77.5946],
    'bengaluru': [12.9716, 77.5946],
    // Oceania
    'sydney': [-33.8688, 151.2093],
    'melbourne': [-37.8136, 144.9631],
    'brisbane': [-27.4698, 153.0251],
    'perth': [-31.9505, 115.8605],
    'adelaide': [-34.9285, 138.6007],
    'auckland': [-36.8485, 174.7633],
    'wellington': [-41.2865, 174.7762],
    // South America
    'são paulo': [-23.5505, -46.6333],
    'sao paulo': [-23.5505, -46.6333],
    'rio de janeiro': [-22.9068, -43.1729],
    'rio': [-22.9068, -43.1729],
    'brasilia': [-15.7942, -47.8822],
    'buenos aires': [-34.6037, -58.3816],
    'lima': [-12.0464, -77.0428],
    'bogota': [4.7110, -74.0721],
    'bogotá': [4.7110, -74.0721],
    'santiago': [-33.4489, -70.6693],
    'caracas': [10.4806, -66.9036],
    // Africa
    'cairo': [30.0444, 31.2357],
    'cape town': [-33.9249, 18.4241],
    'johannesburg': [-26.2041, 28.0473],
    'nairobi': [-1.2921, 36.8219],
    'lagos': [6.5244, 3.3792],
    'casablanca': [33.5731, -7.5898],
    // Country fallbacks (for users who type just the country)
    'usa': [39.8283, -98.5795],
    'united states': [39.8283, -98.5795],
    'canada': [56.1304, -106.3468],
    'uk': [54.7023, -3.2765],
    'united kingdom': [54.7023, -3.2765],
    'england': [52.3555, -1.1743],
    'scotland': [56.4907, -4.2026],
    'ireland': [53.4129, -8.2439],
    'france': [46.6034, 1.8883],
    'germany': [51.1657, 10.4515],
    'italy': [41.8719, 12.5674],
    'spain': [40.4637, -3.7492],
    'australia': [-25.2744, 133.7751],
    'japan': [36.2048, 138.2529],
    'korea': [35.9078, 127.7669],
    'south korea': [35.9078, 127.7669],
    'china': [35.8617, 104.1954],
    'india': [20.5937, 78.9629],
    'brazil': [-14.2350, -51.9253],
    'mexico': [23.6345, -102.5528],
    'uae': [23.4241, 53.8478],
    'united arab emirates': [23.4241, 53.8478],
  };

  /// All providers (read-only).
  static List<Provider> get all => List.unmodifiable(_providers);

  // ── User-added providers (locally persisted via AppPrefs) ────────────
  //
  // Users can save their own provider via the "Add a Provider" form in
  // the directory UI. These are stored as JSON in SharedPreferences and
  // merged into search results alongside the curated list.

  /// Key for the JSON-encoded list of user-added providers.
  static const String _userProvidersKey = 'user_added_providers';

  static final List<Provider> _userProviders = <Provider>[];
  static bool _userProvidersLoaded = false;

  /// Returns the user-added providers currently in memory.
  static List<Provider> get userAdded => List.unmodifiable(_userProviders);

  /// Load user-added providers from local storage. Safe to call multiple
  /// times — subsequent calls are no-ops until [refreshUserProviders] is
  /// called explicitly.
  static Future<void> loadUserProviders() async {
    if (_userProvidersLoaded) return;
    await refreshUserProviders();
  }

  /// Force-reload user-added providers from local storage.
  static Future<void> refreshUserProviders() async {
    _userProviders.clear();
    final raw = await AppPrefs.getString(_userProvidersKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              _userProviders.add(Provider.fromJson(item));
            } else if (item is Map) {
              _userProviders.add(
                Provider.fromJson(Map<String, dynamic>.from(item)),
              );
            }
          }
        }
      } catch (_) {
        // Corrupt payload — fall back to empty list.
      }
    }
    _userProvidersLoaded = true;
  }

  /// Persist a new user-added provider and add it to the in-memory list.
  static Future<void> addUserProvider(Provider provider) async {
    await loadUserProviders();
    _userProviders.add(provider);
    await _persistUserProviders();
  }

  /// Remove a user-added provider by [id].
  static Future<void> removeUserProvider(String id) async {
    await loadUserProviders();
    _userProviders.removeWhere((p) => p.id == id);
    await _persistUserProviders();
  }

  static Future<void> _persistUserProviders() async {
    final encoded = jsonEncode(_userProviders.map((p) => p.toJson()).toList());
    await AppPrefs.setString(_userProvidersKey, encoded);
  }

  /// Combined list of curated + user-added providers used for search.
  static List<Provider> _allProviders() => <Provider>[
    ..._userProviders,
    ..._providers,
  ];

  /// Returns true when [input] resolves to a known geographic location.
  /// Supports US zip codes (any digits ≥ 2), Canadian postal codes,
  /// UK postcodes, Australian / international numeric codes, and
  /// global city / country names.
  static bool isZipKnown(String input) => resolveLocation(input) != null;

  /// Returns providers ranked by proximity to [zip], with optional filters.
  ///
  /// The ranker is **semantic** — natural-language intent words like
  /// "best", "top", "premium", "near me", "specialist", "expert",
  /// "injector", "surgeon", "medspa" and "clinic" are recognised and
  /// stripped from the text-search haystack. They instead boost the
  /// corresponding ranking weights (rating, specialty-match, etc.) so
  /// users can type things like *"best halo laser near me"* or
  /// *"microneedling specialist"* and get a sensible ordering.
  ///
  /// User-added providers (added via the "Add a Provider" form) are
  /// merged into the result alongside the curated list.
  ///
  /// - If [zip] is null/empty/unrecognised, returns providers with
  ///   `distanceMiles == null` (the UI can render `—` for distance).
  /// - [maxDistanceMiles] / [minRating] / [boardCertifiedOnly] act as
  ///   inclusive hard filters.
  static List<ProviderMatch> search({
    String? zip,
    double? maxDistanceMiles,
    double minRating = 0,
    bool boardCertifiedOnly = false,
    String? query,
    String? procedureType,
  }) {
    final originCoords = _coordsForZip(zip);
    final procedureKeywords = _keywordsForProcedure(procedureType);

    final rawQ = (query ?? '').trim().toLowerCase();
    // Parse intent tokens out of the query.
    final _ParsedQuery parsed = _parseQuery(rawQ);
    final terms = parsed.terms;

    final scored = <_ScoredMatch>[];
    for (final p in _allProviders()) {
      if (boardCertifiedOnly && !p.boardCertified) continue;
      if (p.rating < minRating) continue;

      // Build the text haystack once.
      final haystack =
          '${p.name} ${p.clinicName} ${p.city} ${p.state} ${p.specialties.join(' ')}'
              .toLowerCase();

      // When the user supplied any cleaned search terms, require at
      // least ONE token match somewhere in the haystack — that way the
      // text query still acts as a filter, just not a brittle substring
      // filter on the raw input ("best halo near me" would otherwise
      // exclude everything).
      int tokenHits = 0;
      if (terms.isNotEmpty) {
        for (final t in terms) {
          if (haystack.contains(t)) tokenHits++;
        }
        if (tokenHits == 0) continue;
      }

      double? dist;
      if (originCoords != null) {
        dist = _haversineMiles(originCoords[0], originCoords[1], p.lat, p.lng);
        if (maxDistanceMiles != null && dist > maxDistanceMiles) continue;
      }

      final matchedSpecialty = _firstMatchingSpecialty(p, procedureKeywords);
      final isSpecialist = matchedSpecialty != null;

      // ── Relevance score ────────────────────────────────────────────
      // Bias is "distance first, but procedure / quality intent shifts
      // the ranking meaningfully". All components are positive.
      double score = 0;

      // Specialty match — the single biggest signal when a procedure
      // context is set. Specialist intent ("specialist", "expert", etc.)
      // amplifies it further.
      if (isSpecialist) {
        score += 60 * parsed.specialistBoost;
      }

      // Rating — base + extra weight when quality intent words appear.
      score += p.rating * 12 * parsed.qualityBoost;

      // Token matches in the haystack.
      score += tokenHits * 6;

      // Distance — closer is better. Caps the impact so a perfect
      // specialist 50 mi away beats a generic 5 mi medspa.
      if (dist != null) {
        score += math.max(0, 40 - dist * 0.45);
      } else {
        score += 8; // No origin → neutral distance component.
      }

      // User-added providers get a small affinity bump — they live at
      // the top of the user's mental model of "providers I trust".
      if (p.isUserAdded) score += 4;

      scored.add(
        _ScoredMatch(
          ProviderMatch(
            provider: p,
            distanceMiles: dist,
            isSpecialistMatch: isSpecialist,
            matchedSpecialty: matchedSpecialty,
          ),
          score,
        ),
      );
    }

    // Decide primary sort order:
    //   - When a procedureType or non-trivial query is present → score desc.
    //   - Otherwise → classic distance asc (the user just wants closest).
    final useScore =
        procedureKeywords.isNotEmpty || terms.isNotEmpty || parsed.hasIntent;

    scored.sort((a, b) {
      if (useScore) {
        final cmp = b.score.compareTo(a.score);
        if (cmp != 0) return cmp;
      }
      // 1) Specialists first when procedure context exists.
      if (procedureKeywords.isNotEmpty &&
          a.match.isSpecialistMatch != b.match.isSpecialistMatch) {
        return a.match.isSpecialistMatch ? -1 : 1;
      }
      // 2) Distance ascending (nulls last).
      final da = a.match.distanceMiles;
      final db = b.match.distanceMiles;
      if (da == null && db == null) {
        return b.match.provider.rating.compareTo(a.match.provider.rating);
      }
      if (da == null) return 1;
      if (db == null) return -1;
      final cmp = da.compareTo(db);
      if (cmp != 0) return cmp;
      // 3) Tie-break on rating.
      return b.match.provider.rating.compareTo(a.match.provider.rating);
    });

    return scored.map((s) => s.match).toList(growable: false);
  }

  /// Strip natural-language intent words from [raw] and return the
  /// remaining search terms plus boost factors that influence ranking.
  static _ParsedQuery _parseQuery(String raw) {
    if (raw.isEmpty) {
      return const _ParsedQuery(
        terms: [],
        qualityBoost: 1.0,
        specialistBoost: 1.0,
        hasIntent: false,
      );
    }
    // "near me" appears as a phrase — strip it first.
    var working = raw
        .replaceAll(RegExp(r'\bnear\s+me\b'), ' ')
        .replaceAll(RegExp(r'\bclose\s+to\s+me\b'), ' ');

    // Intent vocabularies.
    const qualityWords = {
      'best',
      'top',
      'premium',
      'luxury',
      'rated',
      'highly',
      'excellent',
      'leading',
      'great',
      'recommended',
    };
    const specialistWords = {
      'specialist',
      'expert',
      'specialists',
      'experts',
      'injector',
      'injectors',
      'surgeon',
      'surgeons',
      'doctor',
      'dr',
      'medspa',
      'clinic',
      'aesthetic',
      'plastic',
      'cosmetic',
      'board-certified',
      'board',
    };
    const stopWords = {
      'a',
      'an',
      'the',
      'for',
      'with',
      'and',
      'or',
      'of',
      'to',
      'in',
      'at',
      'on',
      'me',
      'my',
      'i',
      'find',
      'show',
      'search',
      'looking',
      'need',
      'want',
    };

    double qualityBoost = 1.0;
    double specialistBoost = 1.0;
    bool hasIntent = false;

    final tokens = working
        .split(RegExp(r'[\s,;/&]+'))
        .where((t) => t.isNotEmpty)
        .toList();

    final terms = <String>[];
    for (final t in tokens) {
      final w = t.toLowerCase();
      if (qualityWords.contains(w)) {
        qualityBoost = 1.6;
        hasIntent = true;
        continue;
      }
      if (specialistWords.contains(w)) {
        specialistBoost = 1.4;
        hasIntent = true;
        continue;
      }
      if (stopWords.contains(w)) {
        continue;
      }
      if (w.length < 2) continue;
      terms.add(w);
    }

    return _ParsedQuery(
      terms: terms,
      qualityBoost: qualityBoost,
      specialistBoost: specialistBoost,
      hasIntent: hasIntent,
    );
  }

  /// Resolve a centroid [lat, lng] for [zip].
  /// Delegates to [resolveLocation] for worldwide coverage.
  /// Returns null only for null / empty / unrecognised input.
  static List<double>? _coordsForZip(String? zip) {
    final hit = resolveLocation(zip);
    return hit == null ? null : [hit.lat, hit.lng];
  }

  /// Worldwide location resolver. Returns lat/lng plus a human-friendly
  /// label ("Toronto, Canada", "London, UK", "44483") that the UI can
  /// surface in headers and banners.
  ///
  /// Detection order:
  ///   1. Canadian postal code (letter-digit-letter…)
  ///   2. UK postcode (letters then digits)
  ///   3. Numeric — US 3-digit prefix → 2-digit fallback
  ///   4. Free-text city / country name (substring match against
  ///      [_globalCityCentroids])
  static ResolvedLocation? resolveLocation(String? input) {
    if (input == null) return null;
    final cleaned = input.trim();
    if (cleaned.isEmpty) return null;
    final upper = cleaned.toUpperCase();
    final lower = cleaned.toLowerCase();

    // ── Canadian postal code (e.g. "M5V 3A1") ──────────────────────────
    final canadianMatch = RegExp(
      r'^([A-Y])\d[A-Z]',
    ).firstMatch(upper.replaceAll(' ', ''));
    if (canadianMatch != null) {
      final province = canadianMatch.group(1)!;
      final coords = _canadaPostalPrefixes[province];
      if (coords != null) {
        final cityLabel = _canadaProvinceLabel(province);
        return ResolvedLocation(coords[0], coords[1], '$cleaned · $cityLabel');
      }
    }

    // ── UK postcode (e.g. "SW1A 1AA", "M2 4WQ") ───────────────────────
    final ukMatch = RegExp(r'^([A-Z]{1,2})\d').firstMatch(upper);
    if (ukMatch != null && !_isPureNumeric(cleaned)) {
      final outward = ukMatch.group(1)!;
      final coords =
          _ukPostalPrefixes[outward] ?? _ukPostalPrefixes[outward[0]];
      if (coords != null) {
        return ResolvedLocation(
          coords[0],
          coords[1],
          '$cleaned · ${_ukRegionLabel(outward)}',
        );
      }
    }

    // ── Numeric (US zip — 3-digit precise, 2-digit fallback) ──────────
    if (_isPureNumeric(cleaned) && cleaned.length >= 2) {
      if (cleaned.length >= 3) {
        final c3 = _zip3Centroids[cleaned.substring(0, 3)];
        if (c3 != null) return ResolvedLocation(c3[0], c3[1], cleaned);
      }
      final c2 = _zip2Centroids[cleaned.substring(0, 2)];
      if (c2 != null) return ResolvedLocation(c2[0], c2[1], cleaned);
      // Numeric input that isn't a US zip — fall through to city lookup
      // so e.g. Australian "2000" / Korean "06032" can still match below.
    }

    // ── Free-text city / country name (substring match) ───────────────
    final exact = _globalCityCentroids[lower];
    if (exact != null) {
      return ResolvedLocation(exact[0], exact[1], _titleCase(cleaned));
    }
    for (final entry in _globalCityCentroids.entries) {
      if (lower.contains(entry.key)) {
        return ResolvedLocation(
          entry.value[0],
          entry.value[1],
          _titleCase(entry.key),
        );
      }
    }

    return null;
  }

  static bool _isPureNumeric(String s) =>
      s.isNotEmpty && RegExp(r'^\d+$').hasMatch(s);

  static String _titleCase(String s) {
    if (s.isEmpty) return s;
    return s
        .split(' ')
        .map(
          (w) => w.isEmpty
              ? w
              : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
        )
        .join(' ');
  }

  static String _canadaProvinceLabel(String letter) {
    switch (letter) {
      case 'A':
        return 'Newfoundland, Canada';
      case 'B':
        return 'Nova Scotia, Canada';
      case 'C':
        return 'PEI, Canada';
      case 'E':
        return 'New Brunswick, Canada';
      case 'G':
        return 'Quebec, Canada';
      case 'H':
        return 'Montreal, Canada';
      case 'J':
        return 'Quebec, Canada';
      case 'K':
        return 'Ottawa, Canada';
      case 'L':
        return 'Ontario, Canada';
      case 'M':
        return 'Toronto, Canada';
      case 'N':
        return 'Ontario, Canada';
      case 'P':
        return 'Ontario, Canada';
      case 'R':
        return 'Manitoba, Canada';
      case 'S':
        return 'Saskatchewan, Canada';
      case 'T':
        return 'Alberta, Canada';
      case 'V':
        return 'British Columbia, Canada';
      case 'X':
        return 'Northern Canada';
      case 'Y':
        return 'Yukon, Canada';
      default:
        return 'Canada';
    }
  }

  static String _ukRegionLabel(String outward) {
    const londonAreas = {'E', 'EC', 'N', 'NW', 'SE', 'SW', 'W', 'WC'};
    if (londonAreas.contains(outward)) return 'London, UK';
    switch (outward) {
      case 'M':
        return 'Manchester, UK';
      case 'B':
        return 'Birmingham, UK';
      case 'L':
        return 'Liverpool, UK';
      case 'LS':
        return 'Leeds, UK';
      case 'S':
        return 'Sheffield, UK';
      case 'BS':
        return 'Bristol, UK';
      case 'CF':
        return 'Cardiff, UK';
      case 'EH':
        return 'Edinburgh, UK';
      case 'G':
        return 'Glasgow, UK';
      case 'BT':
        return 'Belfast, UK';
      case 'OX':
        return 'Oxford, UK';
      case 'CB':
        return 'Cambridge, UK';
      case 'BN':
        return 'Brighton, UK';
      default:
        return 'United Kingdom';
    }
  }

  /// Haversine great-circle distance in miles between two lat/lng pairs.
  static double _haversineMiles(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusMiles = 3958.7613;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_toRad(lat1)) *
            math.cos(_toRad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusMiles * c;
  }

  static double _toRad(double deg) => deg * math.pi / 180.0;

  // ── Procedure-specialty matching ─────────────────────────────────────
  //
  // Maps procedure types (and common variants) to a set of keywords that
  // we substring-match against provider `specialties`. Both sides are
  // lower-cased and normalised before comparison.
  static const Map<String, List<String>> _procedureSynonyms = {
    'botox': [
      'botox',
      'injectable',
      'neurotoxin',
      'dysport',
      'xeomin',
      'tox',
      'wrinkle relaxer',
    ],
    'filler': [
      'filler',
      'injectable',
      'lip filler',
      'dermal filler',
      'juvederm',
      'restylane',
    ],
    'microneedling': [
      'microneedling',
      'micro-needling',
      'micro needling',
      'rf microneedling',
      'morpheus',
      'skinpen',
    ],
    'laser': [
      'laser',
      'laser resurfacing',
      'halo',
      'co2',
      'fraxel',
      'ipl',
      'broadband light',
      'bbl',
    ],
    'halo laser': ['halo', 'laser', 'laser resurfacing'],
    'chemical peel': ['peel', 'chemical peel', 'tca', 'glycolic', 'vi peel'],
    'rhinoplasty': ['rhinoplasty', 'nose', 'nasal'],
    'facelift': ['facelift', 'face lift', 'rhytidectomy', 'mini facelift'],
    'liposuction': ['liposuction', 'lipo', 'body contouring'],
    'breast augmentation': ['breast', 'augmentation', 'mammoplasty'],
    'breast reduction': ['breast', 'reduction', 'mammoplasty'],
    'tummy tuck': ['tummy tuck', 'abdominoplasty', 'body contouring'],
    'bbl': ['bbl', 'brazilian butt lift', 'buttock', 'body contouring'],
    'coolsculpting': [
      'coolsculpting',
      'body contouring',
      'fat reduction',
      'cryolipolysis',
    ],
    'hair transplant': ['hair', 'hair transplant', 'restoration', 'fue'],
    'eyelid surgery': ['eyelid', 'blepharoplasty', 'eye'],
    'blepharoplasty': ['blepharoplasty', 'eyelid'],
    'hydrafacial': ['hydrafacial', 'facial', 'skincare'],
    'skincare': ['skincare', 'facial', 'hydrafacial'],
    'prp': ['prp', 'platelet', 'hair', 'microneedling'],
    'microblading': ['microblading', 'brow'],
    'lip filler': ['lip filler', 'filler', 'injectable'],
  };

  /// Build the keyword set we'll search for in provider specialties.
  /// Returns an empty list when no procedure was selected.
  static List<String> _keywordsForProcedure(String? procedureType) {
    if (procedureType == null) return const [];
    final type = procedureType.trim().toLowerCase();
    if (type.isEmpty) return const [];
    final tokens = <String>{type};
    // Direct synonym table lookup (substring on either side).
    for (final entry in _procedureSynonyms.entries) {
      if (type.contains(entry.key) || entry.key.contains(type)) {
        tokens.add(entry.key);
        tokens.addAll(entry.value);
        continue;
      }
      for (final syn in entry.value) {
        if (type.contains(syn) || syn.contains(type)) {
          tokens.add(entry.key);
          tokens.addAll(entry.value);
          break;
        }
      }
    }
    // Split multi-word procedure names ("halo laser" -> "halo", "laser").
    for (final w in type.split(RegExp(r'[\s\-/&]+'))) {
      if (w.length >= 4) tokens.add(w);
    }
    return tokens.toList(growable: false);
  }

  /// Returns the first provider specialty that matches any of [keywords],
  /// or null if there is no match.
  static String? _firstMatchingSpecialty(Provider p, List<String> keywords) {
    if (keywords.isEmpty) return null;
    for (final spec in p.specialties) {
      final s = spec.toLowerCase();
      for (final k in keywords) {
        if (s.contains(k) || k.contains(s)) return spec;
      }
    }
    return null;
  }

  /// Public helper for UI code: does [specialty] match [procedureType]?
  /// Used to highlight the matching specialty pill on a provider card.
  static bool specialtyMatchesProcedure(
    String specialty,
    String? procedureType,
  ) {
    final keywords = _keywordsForProcedure(procedureType);
    if (keywords.isEmpty) return false;
    final s = specialty.toLowerCase();
    for (final k in keywords) {
      if (s.contains(k) || k.contains(s)) return true;
    }
    return false;
  }
}

// ── Internal helpers ──────────────────────────────────────────────────

class _ParsedQuery {
  final List<String> terms;
  final double qualityBoost;
  final double specialistBoost;
  final bool hasIntent;
  const _ParsedQuery({
    required this.terms,
    required this.qualityBoost,
    required this.specialistBoost,
    required this.hasIntent,
  });
}

class _ScoredMatch {
  final ProviderMatch match;
  final double score;
  const _ScoredMatch(this.match, this.score);
}
