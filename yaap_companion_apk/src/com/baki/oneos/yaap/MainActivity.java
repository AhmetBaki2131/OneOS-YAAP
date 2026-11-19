package com.baki.oneos.yaap;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Context;
import android.graphics.Color;
import android.graphics.Typeface;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.List;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class MainActivity extends Activity {

    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final ExecutorService executor = Executors.newSingleThreadExecutor();

    private LinearLayout cardsContainer;
    private TextView summaryBanner;
    private TextView rootOutputBox;
    private HostFacts.Snapshot lastSnapshot;
    private List<HostFacts.CheckItem> lastChecks;
    private String lastRootText = "";
    private String lastInstalldText = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        scroll.setBackgroundColor(0xFF0A0F18);
        scroll.setFillViewport(true);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(18);
        root.setPadding(pad, dp(42), pad, dp(32));
        scroll.addView(root, new ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT));

        TextView header = new TextView(this);
        header.setText("OneOS YAAP • SM-A055F");
        header.setTextColor(Color.WHITE);
        header.setTextSize(26f);
        header.setTypeface(Typeface.create("sans-serif-medium", Typeface.BOLD));
        root.addView(header);

        TextView subtitle = new TextView(this);
        subtitle.setText("fahadalijaved/OneOS Android 17 YAAP Uyumluluk & Probe Aracı");
        subtitle.setTextColor(0xFF9BB4D0);
        subtitle.setTextSize(13f);
        subtitle.setPadding(0, dp(4), 0, dp(14));
        root.addView(subtitle);

        summaryBanner = new TextView(this);
        summaryBanner.setTextColor(Color.WHITE);
        summaryBanner.setTextSize(14f);
        summaryBanner.setTypeface(Typeface.DEFAULT_BOLD);
        summaryBanner.setPadding(dp(16), dp(14), dp(16), dp(14));
        summaryBanner.setBackgroundResource(R.drawable.bg_glass_card);
        root.addView(summaryBanner);

        LinearLayout btnRow1 = makeButtonRow();
        Button btnScan = makeBtn("Cihazı Yeniden Tara");
        Button btnRoot = makeBtn("Root & Kernel Probe");
        btnRow1.addView(btnScan, weightedLp());
        btnRow1.addView(btnRoot, weightedLp());
        root.addView(btnRow1);

        LinearLayout btnRow2 = makeButtonRow();
        Button btnInstalld = makeBtn("IInstalld (27 Metod) Testi");
        Button btnCopy = makeBtn("Raporu Kopyala");
        btnRow2.addView(btnInstalld, weightedLp());
        btnRow2.addView(btnCopy, weightedLp());
        root.addView(btnRow2);

        cardsContainer = new LinearLayout(this);
        cardsContainer.setOrientation(LinearLayout.VERTICAL);
        root.addView(cardsContainer);

        TextView logTitle = new TextView(this);
        logTitle.setText("Root / IInstalld Çıktısı");
        logTitle.setTextColor(0xFFB5CCE4);
        logTitle.setTextSize(14f);
        logTitle.setTypeface(Typeface.DEFAULT_BOLD);
        logTitle.setPadding(dp(4), dp(16), dp(4), dp(8));
        root.addView(logTitle);

        rootOutputBox = new TextView(this);
        rootOutputBox.setTextColor(0xFFDDE8F5);
        rootOutputBox.setTextSize(11.5f);
        rootOutputBox.setTypeface(Typeface.MONOSPACE);
        rootOutputBox.setPadding(dp(14), dp(14), dp(14), dp(14));
        rootOutputBox.setBackgroundResource(R.drawable.bg_glass_card);
        rootOutputBox.setText("Henüz root veya IInstalld testi çalıştırılmadı.");
        root.addView(rootOutputBox);

        setContentView(scroll);

        btnScan.setOnClickListener(v -> refreshFacts());
        btnRoot.setOnClickListener(v -> runRootCheck());
        btnInstalld.setOnClickListener(v -> runInstalldCheck());
        btnCopy.setOnClickListener(v -> copyReport());

        refreshFacts();
    }

    private void refreshFacts() {
        lastSnapshot = HostFacts.collect(this);
        lastChecks = HostFacts.evaluate(lastSnapshot);
        cardsContainer.removeAllViews();

        int blocks = 0, warns = 0;
        for (HostFacts.CheckItem item : lastChecks) {
            if (item.level == HostFacts.Level.BLOCK) blocks++;
            else if (item.level == HostFacts.Level.WARN) warns++;
            addCheckCard(item);
        }

        if (blocks > 0) {
            summaryBanner.setText("Durum: " + blocks + " Engel (BLOCK), " + warns + " Uyarı • Geçiş öncesi engelleri çöz");
        } else if (warns > 0) {
            summaryBanner.setText("Durum: " + warns + " Uyarı (YAAP Uyarlama Modu) • Donanım hazır");
        } else {
            summaryBanner.setText("Durum: Tüm yerel kontroller OK");
        }
    }

    private void runRootCheck() {
        rootOutputBox.setText("su ile kernel / HAL / watchdog kontrolü çalışıyor...");
        executor.execute(() -> {
            RootProbeRunner.Result res = RootProbeRunner.runKernelAndHalProbe();
            lastRootText = res.output;
            mainHandler.post(() -> rootOutputBox.setText(renderCombinedOutput()));
        });
    }

    private void runInstalldCheck() {
        rootOutputBox.setText("services.jar üzerinden YAAP IInstalld tablosu çıkarılıyor (5-15 sn)...");
        executor.execute(() -> {
            RootProbeRunner.Result res = RootProbeRunner.runInstalldCheck();
            lastInstalldText = res.output;
            mainHandler.post(() -> rootOutputBox.setText(renderCombinedOutput()));
        });
    }

    private String renderCombinedOutput() {
        StringBuilder sb = new StringBuilder();
        if (!lastInstalldText.isEmpty()) {
            sb.append("[IInstalld Doğrulama]\n").append(lastInstalldText).append("\n");
        }
        if (!lastRootText.isEmpty()) {
            sb.append("[Kernel / HAL Probe]\n").append(lastRootText);
        }
        return sb.length() == 0 ? "Çıktı yok." : sb.toString();
    }

    private void copyReport() {
        StringBuilder sb = new StringBuilder();
        if (lastSnapshot != null) {
            sb.append("Model=").append(lastSnapshot.model)
              .append(" Device=").append(lastSnapshot.device)
              .append(" SoC=").append(lastSnapshot.socModel)
              .append(" Platform=").append(lastSnapshot.platform)
              .append(" SDK=").append(lastSnapshot.sdk)
              .append(" Bootloader=").append(lastSnapshot.bootloader)
              .append(" OneUI=").append(lastSnapshot.oneUiRaw)
              .append("\n\n");
        }
        if (lastChecks != null) {
            for (HostFacts.CheckItem c : lastChecks) {
                sb.append("[").append(c.level).append("] ").append(c.title).append(" -> ").append(c.detail).append("\n");
            }
            sb.append("\n");
        }
        sb.append(renderCombinedOutput());

        ClipboardManager cm = (ClipboardManager) getSystemService(Context.CLIPBOARD_SERVICE);
        if (cm != null) {
            cm.setPrimaryClip(ClipData.newPlainText("OneOS YAAP Report", sb.toString()));
            Toast.makeText(this, "Rapor panoya kopyalandı", Toast.LENGTH_SHORT).show();
        }
    }

    private void addCheckCard(HostFacts.CheckItem item) {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        card.setPadding(dp(14), dp(12), dp(14), dp(12));
        card.setBackgroundResource(R.drawable.bg_glass_card);

        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(10);
        card.setLayoutParams(lp);

        TextView badge = new TextView(this);
        int badgeColor;
        switch (item.level) {
            case BLOCK: badgeColor = 0xFFFF5C5C; break;
            case WARN:  badgeColor = 0xFFFFB84D; break;
            case OK:    badgeColor = 0xFF4ADE80; break;
            default:    badgeColor = 0xFF60A5FA; break;
        }
        badge.setText("[" + item.level.name() + "]  " + item.title);
        badge.setTextColor(badgeColor);
        badge.setTextSize(14f);
        badge.setTypeface(Typeface.DEFAULT_BOLD);
        card.addView(badge);

        TextView detail = new TextView(this);
        detail.setText(item.detail);
        detail.setTextColor(0xFFD8E4F2);
        detail.setTextSize(12.5f);
        detail.setPadding(0, dp(4), 0, 0);
        card.addView(detail);

        cardsContainer.addView(card);
    }

    private LinearLayout makeButtonRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT);
        lp.topMargin = dp(10);
        row.setLayoutParams(lp);
        return row;
    }

    private Button makeBtn(String text) {
        Button b = new Button(this);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextColor(Color.WHITE);
        b.setTextSize(12.5f);
        b.setGravity(Gravity.CENTER);
        b.setBackgroundResource(R.drawable.bg_pill_btn);
        b.setPadding(dp(8), dp(10), dp(8), dp(10));
        return b;
    }

    private LinearLayout.LayoutParams weightedLp() {
        LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1f);
        lp.leftMargin = dp(4);
        lp.rightMargin = dp(4);
        return lp;
    }

    private int dp(int v) {
        return Math.round(TypedValue.applyDimension(TypedValue.COMPLEX_UNIT_DIP, v, getResources().getDisplayMetrics()));
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        executor.shutdownNow();
    }
}
