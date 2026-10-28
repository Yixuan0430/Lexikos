import SwiftUI

// Palette after Synaxos: sage paper neutrals, Didot display, swappable accent.
extension Color {
    static func dyn(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? NSColor(hex: dark) : NSColor(hex: light) })
    }
    static let bg = dyn(0xF3F6F4, 0x121615)
    static let panel = dyn(0xFBFCFB, 0x181D1C)
    static let ink = dyn(0x1F2B28, 0xE4EBE8)
    static let muted = dyn(0x596963, 0x98A6A1)
    static let line = dyn(0xDDE5E1, 0x2C3533)
}

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

// MARK: Window-size adaptation

private struct WindowSizeKey: EnvironmentKey { static let defaultValue = CGSize(width: 820, height: 600) }
extension EnvironmentValues {
    var windowSize: CGSize {
        get { self[WindowSizeKey.self] }
        set { self[WindowSizeKey.self] = newValue }
    }
}

extension CGSize {
    /// Side margin: tight on narrow windows, wider on large ones.
    var gutter: CGFloat { width < 640 ? 20 : width < 1100 ? 36 : 56 }
    var compact: Bool { width < 760 }
    /// Type scale for the practice card, relative to the default 820×600 window.
    var cardScale: CGFloat { min(1.5, max(0.72, min(width / 820, height / 600))) }
}

enum Accent: String, CaseIterable, Identifiable {
    case sage, blue, gold, rose, violet, terracotta
    var id: String { rawValue }
    private var hex: (UInt32, UInt32, UInt32, UInt32) { // light, dark, soft light, soft dark
        switch self {
        case .sage: (0x476F61, 0x9CC4AF, 0xE6F1EB, 0x1C2623)
        case .blue: (0x50659A, 0xA9BFE0, 0xE7ECF5, 0x1B2130)
        case .gold: (0x8A6D1E, 0xC9A43B, 0xF4EEDC, 0x29241A)
        case .rose: (0x9A4F6E, 0xDDA8B8, 0xF5E8EC, 0x2B1D22)
        case .violet: (0x6652A8, 0xBFB3DD, 0xEDE9F6, 0x221E2E)
        case .terracotta: (0xA65A33, 0xE8A98D, 0xF7EAE2, 0x2C211B)
        }
    }
    var color: Color { Color.dyn(hex.0, hex.1) }
    var soft: Color { Color.dyn(hex.2, hex.3) }
}

enum Appearance: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    func apply() {
        NSApp.appearance = switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum AppLanguage: String, CaseIterable, Identifiable {
    case zh, en, fr
    var id: String { rawValue }
    var label: String { ["zh": "中文", "en": "English", "fr": "Français"][rawValue]! }
}

/// UI strings in Chinese, English and French.
struct L {
    let lang: AppLanguage
    subscript(_ key: String) -> String { L.table[key]?[lang.rawValue] ?? key }

    private static let table: [String: [String: String]] = [
        "slow": ["zh": "慢速", "en": "Slow", "fr": "Lent"],
        "remaining": ["zh": "剩余", "en": "left", "fr": "restantes"],
        "tap.grade": ["zh": "选择记忆程度", "en": "Rate how well you knew it", "fr": "Évaluez votre mémoire"],
        "keys.study": ["zh": "空格 显示/继续 · 1 没记住 · 2 模糊 · 3 记住了 · S 朗读 · A 慢速", "en": "Space reveal · 1 forgot · 2 vague · 3 knew it · S listen · A slow", "fr": "Espace révéler · 1 oublié · 2 flou · 3 su · S écouter · A lent"],
        "grade.forgot": ["zh": "没记住", "en": "Forgot", "fr": "Oublié"],
        "grade.vague": ["zh": "模糊", "en": "Vague", "fr": "Flou"],
        "grade.remembered": ["zh": "记住了", "en": "Knew it", "fr": "Su"],
        "again.soon": ["zh": "稍后再现", "en": "Again soon", "fr": "Bientôt"],
        "unit.hours": ["zh": "小时后", "en": "h", "fr": "h"],
        "unit.days": ["zh": "天后", "en": "days", "fr": "j"],
        "unit.months": ["zh": "个月后", "en": "months", "fr": "mois"],
        "unit.d": ["zh": "天", "en": "d", "fr": "j"],
        "done.title": ["zh": "今天的任务完成了", "en": "All done for today", "fr": "Terminé pour aujourd’hui"],
        "back.overview": ["zh": "查看记忆曲线", "en": "See memory curve", "fr": "Voir la courbe"],
        "free": ["zh": "自由练习", "en": "Free practice", "fr": "Entraînement libre"],
        "start": ["zh": "开始今日学习", "en": "Start today", "fr": "Commencer"],
        "today": ["zh": "今日", "en": "Today", "fr": "Aujourd’hui"],
        "today.plan": ["zh": "今日计划", "en": "Today’s plan", "fr": "Programme du jour"],
        "today.clear": ["zh": "今日已完成", "en": "All caught up", "fr": "À jour"],
        "review": ["zh": "复习", "en": "Review", "fr": "Révision"],
        "new": ["zh": "新词", "en": "New", "fr": "Nouveaux"],
        "stat.due": ["zh": "待复习", "en": "Due", "fr": "À revoir"],
        "stat.learning": ["zh": "学习中", "en": "Learning", "fr": "En cours"],
        "stat.mastered": ["zh": "已掌握", "en": "Mastered", "fr": "Maîtrisés"],
        "stat.unseen": ["zh": "未学", "en": "Unseen", "fr": "Non vus"],
        "stat.today": ["zh": "今日已学", "en": "Studied today", "fr": "Vus aujourd’hui"],
        "curve.title": ["zh": "遗忘曲线", "en": "Forgetting curve", "fr": "Courbe de l’oubli"],
        "curve.sub": ["zh": "如果从现在起不再复习，你的平均记忆保留率", "en": "Your average recall if you stop reviewing now", "fr": "Votre rétention moyenne sans révision"],
        "curve.ebbinghaus": ["zh": "艾宾浩斯（不复习）", "en": "Ebbinghaus (no review)", "fr": "Ebbinghaus (sans révision)"],
        "curve.yours": ["zh": "你的记忆", "en": "Your memory", "fr": "Votre mémoire"],
        "forecast.title": ["zh": "复习计划", "en": "Review schedule", "fr": "Planning"],
        "forecast.sub": ["zh": "未来 14 天每天要复习的词数", "en": "Cards due each day, next 14 days", "fr": "Cartes à revoir, 14 prochains jours"],
        "words.title": ["zh": "单词记忆", "en": "Word memory", "fr": "Mémoire par mot"],
        "words.sub": ["zh": "按当前记忆保留率排序，点击查看单词的遗忘曲线", "en": "Sorted by current recall; click a word for its curve", "fr": "Triés par rétention ; cliquez pour la courbe"],
        "words.empty": ["zh": "还没有学过的词。点「开始今日学习」开始吧。", "en": "No words studied yet. Press Start today.", "fr": "Aucun mot étudié. Appuyez sur Commencer."],
        "due.now": ["zh": "现在复习", "en": "Due now", "fr": "À revoir"],
        "now": ["zh": "现在", "en": "now", "fr": "maint."],
        "word.sub": ["zh": "每次复习把记忆拉回 100%，曲线越来越平缓 = 记得越来越牢。圆点颜色是当次的记忆程度。", "en": "Each review resets recall to 100%; flatter curves mean stronger memory. Dot colour shows your rating.", "fr": "Chaque révision remet à 100 % ; plus la courbe est plate, plus la mémoire est solide."],
        "word.retention": ["zh": "当前记忆", "en": "Recall now", "fr": "Rétention"],
        "word.stability": ["zh": "记忆强度", "en": "Stability", "fr": "Stabilité"],
        "word.reviews": ["zh": "复习次数", "en": "Reviews", "fr": "Révisions"],
        "word.lapses": ["zh": "遗忘次数", "en": "Lapses", "fr": "Oublis"],
        "word.next": ["zh": "下次复习", "en": "Next review", "fr": "Prochaine"],
        "newPerDay": ["zh": "每日新词数", "en": "New words per day", "fr": "Nouveaux mots par jour"],
        "dur.hours": ["zh": "小时", "en": "h", "fr": "h"],
        "dur.days": ["zh": "天", "en": "days", "fr": "j"],
        "dur.months": ["zh": "个月", "en": "months", "fr": "mois"],
        "cat.examples": ["zh": "例句", "en": "Examples", "fr": "Exemples"],
        "cat.usage": ["zh": "用法说明", "en": "Usage", "fr": "Usage"],
        "cat.expressions": ["zh": "常用表达", "en": "Expressions", "fr": "Expressions"],
        "cat.related": ["zh": "相关词汇", "en": "Related", "fr": "Vocabulaire lié"],
        "cat.grammar": ["zh": "语法", "en": "Grammar", "fr": "Grammaire"],
        "tap.learn": ["zh": "新词：先看一遍，记住它", "en": "New word: take a look first", "fr": "Nouveau mot : regardez-le"],
        "learn.badge": ["zh": "新词 · 学习中", "en": "New word · learning", "fr": "Nouveau · apprentissage"],
        "learn.continue": ["zh": "认识了，继续", "en": "Got it, next", "fr": "Compris, suivant"],
        "autoSpeak": ["zh": "翻开时自动朗读", "en": "Speak when revealed", "fr": "Lecture automatique"],
        "on": ["zh": "开", "en": "On", "fr": "Oui"],
        "off": ["zh": "关", "en": "Off", "fr": "Non"],
        "start.from": ["zh": "从这个词库开始", "en": "Study deck", "fr": "Paquet"],
        "start.go": ["zh": "开始学习", "en": "Start", "fr": "Commencer"],
        "custom": ["zh": "自定义", "en": "Custom", "fr": "Perso"],
        "reimport": ["zh": "重新导入（保留进度）", "en": "Re-import (keep progress)", "fr": "Réimporter (garder la progression)"],
        "update": ["zh": "更新", "en": "Updates", "fr": "Mises à jour"],
        "update.auto": ["zh": "自动检查更新", "en": "Check automatically", "fr": "Vérifier automatiquement"],
        "update.check": ["zh": "检查更新", "en": "Check now", "fr": "Vérifier"],
        "update.checking": ["zh": "正在检查…", "en": "Checking…", "fr": "Vérification…"],
        "update.latest": ["zh": "已是最新版本", "en": "Up to date", "fr": "À jour"],
        "update.current": ["zh": "当前版本", "en": "Current", "fr": "Version"],
        "update.available": ["zh": "新版本可用：", "en": "New version:", "fr": "Nouvelle version :"],
        "update.install": ["zh": "更新并重启", "en": "Update & restart", "fr": "Mettre à jour"],
        "update.later": ["zh": "稍后", "en": "Later", "fr": "Plus tard"],
        "update.downloading": ["zh": "正在下载更新…", "en": "Downloading update…", "fr": "Téléchargement…"],
        "update.installing": ["zh": "正在安装，即将重启…", "en": "Installing, restarting…", "fr": "Installation…"],
        "update.page": ["zh": "打开下载页", "en": "Open download page", "fr": "Page de téléchargement"],
        "update.err.check": ["zh": "无法连接 GitHub 检查更新", "en": "Couldn’t reach GitHub", "fr": "GitHub injoignable"],
        "update.err.download": ["zh": "更新下载失败，请稍后再试", "en": "Download failed, try again later", "fr": "Échec du téléchargement"],
        "update.err.signature": ["zh": "更新包签名校验失败，已取消安装", "en": "Update signature check failed; not installed", "fr": "Signature invalide, installation annulée"],
        "update.err.location": ["zh": "请先把 Lexikos 拖进「应用程序」文件夹再更新", "en": "Move Lexikos to Applications first", "fr": "Déplacez Lexikos dans Applications"],
        "home.title": ["zh": "词库", "en": "Decks", "fr": "Paquets"],
        "home.subtitle": ["zh": "法语词汇与记忆", "en": "French words, remembered", "fr": "Le français, mot à mot"],
        "builtin": ["zh": "内置", "en": "Built-in", "fr": "Intégré"],
        "imported": ["zh": "已导入", "en": "Imported", "fr": "Importés"],
        "numbers.name": ["zh": "法语数字", "en": "French numbers", "fr": "Les nombres"],
        "numbers.desc": ["zh": "0 – 9999，四档随机", "en": "0 – 9999 in four levels", "fr": "0 – 9999, quatre niveaux"],
        "import": ["zh": "导入词库", "en": "Import deck", "fr": "Importer"],
        "import.desc": ["zh": "Anki .apkg · CSV · TXT", "en": "Anki .apkg · CSV · TXT", "fr": "Anki .apkg · CSV · TXT"],
        "import.failed": ["zh": "导入失败", "en": "Import failed", "fr": "Échec de l’importation"],
        "err.anki21b": ["zh": "这是新版 Anki 格式。请在 Anki 导出时勾选「支持旧版 Anki」后再导入。",
                        "en": "This is the newer Anki format. Re-export with “Support older Anki versions” checked.",
                        "fr": "Format Anki récent. Réexportez en cochant « Prise en charge des anciennes versions »."],
        "err.empty": ["zh": "没有找到卡片。", "en": "No cards found.", "fr": "Aucune carte trouvée."],
        "err.unreadable": ["zh": "无法读取这个文件。", "en": "Could not read this file.", "fr": "Fichier illisible."],
        "cards": ["zh": "张卡片", "en": "cards", "fr": "cartes"],
        "delete": ["zh": "删除", "en": "Delete", "fr": "Supprimer"],
        "ok": ["zh": "好", "en": "OK", "fr": "OK"],
        "settings": ["zh": "设置", "en": "Settings", "fr": "Réglages"],
        "language": ["zh": "界面语言", "en": "Language", "fr": "Langue"],
        "appearance": ["zh": "外观", "en": "Appearance", "fr": "Apparence"],
        "system": ["zh": "跟随系统", "en": "System", "fr": "Système"],
        "light": ["zh": "日间", "en": "Light", "fr": "Jour"],
        "dark": ["zh": "夜间", "en": "Dark", "fr": "Nuit"],
        "accent": ["zh": "主题色", "en": "Accent", "fr": "Couleur"],
        "back": ["zh": "词库", "en": "Decks", "fr": "Paquets"],
        "tap.reveal": ["zh": "点击显示答案", "en": "Click to reveal", "fr": "Cliquez pour révéler"],
        "tap.next": ["zh": "点击下一个", "en": "Click for next", "fr": "Cliquez pour le suivant"],
        "keys.deck": ["zh": "空格 显示/下一个 · D 说明 · → 跳过 · S 朗读", "en": "Space reveal/next · D notes · → skip · S listen",
                      "fr": "Espace révéler/suivant · D notes · → passer · S écouter"],
        "details.show": ["zh": "展开说明", "en": "Show notes", "fr": "Voir les notes"],
        "details.hide": ["zh": "收起说明", "en": "Hide notes", "fr": "Masquer les notes"],
        "keys": ["zh": "空格 显示/下一个 · → 跳过 · S 朗读", "en": "Space reveal/next · → skip · S listen",
                 "fr": "Espace révéler/suivant · → passer · S écouter"],
        "seen": ["zh": "已看", "en": "seen", "fr": "vus"],
        "listen": ["zh": "朗读", "en": "Listen", "fr": "Écouter"],
        "accent.sage": ["zh": "鼠尾草", "en": "Sage", "fr": "Sauge"],
        "accent.blue": ["zh": "雾蓝", "en": "Blue", "fr": "Bleu"],
        "accent.gold": ["zh": "琥珀", "en": "Gold", "fr": "Or"],
        "accent.rose": ["zh": "玫瑰", "en": "Rose", "fr": "Rose"],
        "accent.violet": ["zh": "紫藤", "en": "Violet", "fr": "Violet"],
        "accent.terracotta": ["zh": "陶土", "en": "Terracotta", "fr": "Terre cuite"],
    ]
}
