import 'package:flutter/material.dart';

/// Represents a default, bundled domain blocking category in Theja's Aura.
class AuraDefaultCategory {
  final String name;
  final String description;
  final IconData icon;
  final List<String> domains;

  const AuraDefaultCategory({
    required this.name,
    required this.description,
    required this.icon,
    required this.domains,
  });

  int get domainCount => domains.length;
}

/// Curated bundled category blocklist data for Theja's Aura.
/// Matches the exact static blocklists bundled in the native extension:
/// - ios/AuraTunnel/Resources/categories/ads.txt (49 domains)
/// - ios/AuraTunnel/Resources/categories/trackers.txt (60 domains)
/// - ios/AuraTunnel/Resources/categories/analytics.txt (55 domains)
class AuraDefaultCategoryData {
  static const List<String> adsDomains = [
    "doubleclick.net",
    "googleads.g.doubleclick.net",
    "pagead2.googlesyndication.com",
    "adservice.google.com",
    "ads.pubmatic.com",
    "adnxs.com",
    "ib.adnxs.com",
    "c.amazon-adsystem.com",
    "aax.amazon-adsystem.com",
    "advertising.apple.com",
    "iadsdk.apple.com",
    "ads.yahoo.com",
    "gemini.yahoo.com",
    "taboola.com",
    "trc.taboola.com",
    "outbrain.com",
    "widgets.outbrain.com",
    "rubiconproject.com",
    "fastlane.rubiconproject.com",
    "openx.net",
    "delivery.openx.net",
    "criteo.com",
    "static.criteo.net",
    "casalemedia.com",
    "adroll.com",
    "d.adroll.com",
    "smartadserver.com",
    "applovin.com",
    "ads.mopub.com",
    "unityads.unity3d.com",
    "vungle.com",
    "chartboost.com",
    "inmobi.com",
    "ironsrc.com",
    "media.net",
    "popads.net",
    "adcolony.com",
    "spotxchange.com",
    "sovrn.com",
    "sharethrough.com",
    "triplelift.com",
    "indexexchange.com",
    "teads.tv",
    "revcontent.com",
    "gumgum.com",
    "bidswitch.net",
    "adtechus.com",
    "yieldmo.com",
    "undertone.com",
  ];

  static const List<String> trackersDomains = [
    "scorecardresearch.com",
    "b.scorecardresearch.com",
    "pixel.facebook.com",
    "tr.snapchat.com",
    "analytics.tiktok.com",
    "ads.linkedin.com",
    "px.ads.linkedin.com",
    "bat.bing.com",
    "crwdcntrl.net",
    "bcp.crwdcntrl.net",
    "moatads.com",
    "z.moatads.com",
    "quantserve.com",
    "pixel.quantserve.com",
    "branch.io",
    "app.link",
    "appsflyer.com",
    "t.appsflyer.com",
    "adjust.com",
    "app.adjust.com",
    "singular.net",
    "kochava.com",
    "api.kochava.com",
    "branchster.org",
    "taplytics.com",
    "attribution.braze.com",
    "track.hubspot.com",
    "click.google-analytics.com",
    "telemetry.app.com",
    "bluekai.com",
    "tags.bluekai.com",
    "demdex.net",
    "dpm.demdex.net",
    "krxd.net",
    "beacon.krxd.net",
    "liadm.com",
    "rlcdn.com",
    "eyeota.net",
    "exelator.com",
    "agkn.com",
    "mookie1.com",
    "zemanta.com",
    "lotame.com",
    "btrll.com",
    "addthis.com",
    "s7.addthis.com",
    "sharethis.com",
    "histats.com",
    "chartbeat.com",
    "ping.chartbeat.net",
    "statcounter.com",
    "c.statcounter.com",
    "parsely.com",
    "srv.carbonads.net",
    "proclivitysystems.com",
    "mxptint.net",
    "imrworldwide.com",
    "voicefive.com",
    "research-int.com",
    "comscore.com",
  ];

  static const List<String> analyticsDomains = [
    "google-analytics.com",
    "ssl.google-analytics.com",
    "analytics.google.com",
    "analytics.facebook.com",
    "graph.facebook.com",
    "api.mixpanel.com",
    "decide.mixpanel.com",
    "segment.io",
    "api.segment.io",
    "cdn.segment.com",
    "heapanalytics.com",
    "api.heap.io",
    "amplitude.com",
    "api.amplitude.com",
    "api2.amplitude.com",
    "hotjar.com",
    "static.hotjar.com",
    "clarity.ms",
    "c.bing.com",
    "telemetry.microsoft.com",
    "vortex.data.microsoft.com",
    "settings-win.data.microsoft.com",
    "flurry.com",
    "data.flurry.com",
    "app-measurement.com",
    "app.getsentry.com",
    "browser.sentry-cdn.com",
    "o1.ingest.sentry.io",
    "crashlytics.com",
    "reports.crashlytics.com",
    "fullstory.com",
    "rs.fullstory.com",
    "loggly.com",
    "logs-01.loggly.com",
    "logentries.com",
    "datadoghq.com",
    "browser-http-intake.logs.datadoghq.com",
    "newrelic.com",
    "bam.nr-data.net",
    "js-agent.newrelic.com",
    "mouseflow.com",
    "smartlook.com",
    "api.smartlook.com",
    "count.ly",
    "matomo.org",
    "piwik.pro",
    "kissmetrics.com",
    "tr.kissmetrics.com",
    "crazyegg.com",
    "script.crazyegg.com",
    "luckyorange.com",
    "upload.luckyorange.net",
    "gosquared.com",
    "inspectlet.com",
    "woopra.com",
  ];

  static const List<AuraDefaultCategory> categories = [
    AuraDefaultCategory(
      name: 'Ads',
      description: 'Known advertising networks & ad-serving servers',
      icon: Icons.ad_units,
      domains: adsDomains,
    ),
    AuraDefaultCategory(
      name: 'Trackers',
      description: 'Behavioral tracking, fingerprinting & attribution',
      icon: Icons.track_changes,
      domains: trackersDomains,
    ),
    AuraDefaultCategory(
      name: 'Analytics',
      description: 'Telemetry, usage metrics & diagnostics services',
      icon: Icons.analytics_outlined,
      domains: analyticsDomains,
    ),
  ];

  static AuraDefaultCategory? forName(String name) {
    try {
      return categories.firstWhere(
        (c) => c.name.toLowerCase() == name.toLowerCase(),
      );
    } catch (_) {
      return null;
    }
  }

  static List<String> getDomainsForCategory(String category) {
    return forName(category)?.domains ?? const [];
  }

  static int getDomainCountForCategory(String category) {
    return forName(category)?.domainCount ?? 0;
  }

  static final Map<String, Set<String>> allCategoriesMap = {
    'Ads': adsDomains.toSet(),
    'Trackers': trackersDomains.toSet(),
    'Analytics': analyticsDomains.toSet(),
  };

  static final Set<String> allBundledDomains = {
    ...adsDomains,
    ...trackersDomains,
    ...analyticsDomains,
  };
}
