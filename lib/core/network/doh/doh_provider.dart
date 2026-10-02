enum DohProvider {
  cloudflare(
    'Cloudflare (Default)',
    '1.1.1.1 (Fast, privacy-focused)',
    primaryUrl: 'https://1.1.1.1/dns-query',
    secondaryUrl: 'https://1.0.0.1/dns-query',
    hostHeader: 'cloudflare-dns.com',
    acceptHeader: 'application/dns-json',
    bootstrapIps: ['1.1.1.1', '1.0.0.1'],
  ),
  google(
    'Google',
    '8.8.8.8 (Global & reliable)',
    primaryUrl: 'https://8.8.8.8/resolve',
    secondaryUrl: 'https://8.8.4.4/resolve',
    hostHeader: 'dns.google',
    acceptHeader: 'application/json',
    bootstrapIps: ['8.8.8.8', '8.8.4.4'],
  ),
  quad9(
    'Quad9 (Anti-Censorship)',
    '9.9.9.9 (Bypasses ISP blocks & malicious filters)',
    primaryUrl: 'https://9.9.9.9/dns-query',
    secondaryUrl: 'https://149.112.112.112/dns-query',
    hostHeader: 'dns.quad9.net',
    acceptHeader: 'application/dns-json',
    bootstrapIps: ['9.9.9.9', '149.112.112.112'],
  ),
  adguard(
    'AdGuard (Ad-Blocking)',
    '94.140.14.14 (Bypasses ISP blocks & removes ads)',
    primaryUrl: 'https://dns.adguard-dns.com/dns-query',
    secondaryUrl: 'https://94.140.14.14/dns-query',
    hostHeader: 'dns.adguard-dns.com',
    acceptHeader: 'application/dns-json',
    bootstrapIps: ['94.140.14.14', '94.140.15.15'],
  ),
  system(
    'System (Disabled)',
    'Use device default DNS resolver',
    primaryUrl: '',
    secondaryUrl: '',
    hostHeader: '',
    acceptHeader: '',
    bootstrapIps: [],
  );

  final String title;
  final String description;
  final String primaryUrl;
  final String secondaryUrl;
  final String hostHeader;
  final String acceptHeader;
  final List<String> bootstrapIps;

  const DohProvider(
    this.title,
    this.description, {
    required this.primaryUrl,
    required this.secondaryUrl,
    required this.hostHeader,
    required this.acceptHeader,
    required this.bootstrapIps,
  });

  bool get isDoh => this != DohProvider.system;
}
