class LuxeMockData {
  const LuxeMockData._();

  static Map<String, dynamic> getMockTimelinePayload() {
    return {
      'status': 'success',
      'success': true,
      'baseline': {
        'redness_a_star_p95': 152.4,
        'texture_laplacian_variance': 240.5,
      },
      'current': {
        'redness_a_star_p95': 134.1,
        'texture_laplacian_variance': 35.2,
      },
    };
  }
}
