import SwiftUI
import Charts
import FirebaseFirestore
import FirebaseAuth
import FirebaseFunctions

// MARK: - Historical Progress Models
struct ProgressSnapshot {
    let weekNumber: Int
    let date: Date
    let integrationScore: Double
    let hijackFrequency: Int
    let recoveryRate: Double
    let moodStability: Double
    let agencyRatio: Double
    let ritualEffectiveness: Double
    let dominantTriggers: [String]
    let topNeeds: [String]
    let weeklyGrade: String
}

struct TrendData {
    let improvementTrend: Double // -1 to 1, negative = declining, positive = improving
    let consistencyScore: Double // 0 to 1, how consistent the metrics are
    let projectedScore: Double // predicted next week score
    let bestMetric: String // which area is performing best
    let focusArea: String // which area needs most improvement
}

// MARK: - Historical Analytics Manager
@MainActor
class HistoricalAnalyticsManager: ObservableObject {
    @Published var progressSnapshots: [ProgressSnapshot] = []
    @Published var trendData: TrendData?
    @Published var isLoading = false
    
    private let db = Firestore.firestore()
    
    func loadHistoricalData() {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        isLoading = true
        
        // Use the correct collection name from your WeeklyAnalysisManager
        db.collection("users")
            .document(userId)
            .collection("analyses") // This matches your actual collection name
            .order(by: "createdAt", descending: false)
            .limit(to: 12) // Last 12 weeks
            .getDocuments { [weak self] snapshot, error in
                guard let self = self else { return }
                
                DispatchQueue.main.async {
                    self.isLoading = false
                    
                    if let documents = snapshot?.documents {
                        self.progressSnapshots = documents.compactMap { doc in
                            self.parseProgressSnapshot(from: doc.data())
                        }.sorted { $0.date < $1.date } // Ensure chronological order
                        self.calculateTrends()
                    }
                }
            }
    }
    
    private func calculateTrends() {
        guard progressSnapshots.count >= 2 else {
            trendData = TrendData(
                improvementTrend: 0,
                consistencyScore: 0,
                projectedScore: progressSnapshots.last?.integrationScore ?? 0,
                bestMetric: "None",
                focusArea: "Gather more data"
            )
            return
        }
        
        let scores = progressSnapshots.map { $0.integrationScore }
        let trend = calculateTrendSlope(values: scores)
        let consistency = calculateConsistency(values: scores)
        let projected = predictNextScore(scores: scores)
        let (best, focus) = analyzeBestAndWorstMetrics()
        
        trendData = TrendData(
            improvementTrend: trend,
            consistencyScore: consistency,
            projectedScore: projected,
            bestMetric: best,
            focusArea: focus
        )
    }
    
    private func calculateTrendSlope(values: [Double]) -> Double {
        guard values.count >= 2 else { return 0 }
        
        let n = Double(values.count)
        let x = Array(0..<values.count).map { Double($0) }
        let y = values
        
        let sumX = x.reduce(0, +)
        let sumY = y.reduce(0, +)
        let sumXY = zip(x, y).map(*).reduce(0, +)
        let sumX2 = x.map { $0 * $0 }.reduce(0, +)
        
        let slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX)
        return max(-1.0, min(1.0, slope / 10.0)) // Normalize to -1,1 range
    }
    
    private func calculateConsistency(values: [Double]) -> Double {
        guard values.count > 1 else { return 1.0 }
        
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
        let standardDeviation = sqrt(variance)
        
        // Lower deviation = higher consistency
        return max(0, min(1.0, 1.0 - (standardDeviation / 50.0)))
    }
    
    private func predictNextScore(scores: [Double]) -> Double {
        guard scores.count >= 2 else { return scores.last ?? 0 }
        
        let trend = calculateTrendSlope(values: scores)
        let lastScore = scores.last ?? 0
        let predicted = lastScore + (trend * 10) // Apply trend for next week
        
        return max(0, min(100, predicted))
    }
    
    private func analyzeBestAndWorstMetrics() -> (String, String) {
        guard let latest = progressSnapshots.last else { return ("None", "Gather more data") }
        
        let metrics: [(String, Double)] = [
            ("Integration Score", latest.integrationScore),
            ("Recovery Rate", latest.recoveryRate),
            ("Mood Stability", latest.moodStability),
            ("Agency Ratio", latest.agencyRatio * 100),
            ("Ritual Effectiveness", latest.ritualEffectiveness * 20) // Scale to 0-100
        ]
        
        let best = metrics.max(by: { $0.1 < $1.1 })?.0 ?? "None"
        let worst = metrics.min(by: { $0.1 < $1.1 })?.0 ?? "None"
        
        return (best, worst)
    }
    
    private func parseProgressSnapshot(from data: [String: Any]) -> ProgressSnapshot? {
        // Parse the exact structure from your WeeklyAnalysisManager
        guard
            let createdAt = data["createdAt"] as? Timestamp,
            let enhancedAnalysisDict = data["enhancedAnalysis"] as? [String: Any]
        else { return nil }
        
        // Parse integration score and grade
        guard let integrationScore = enhancedAnalysisDict["integrationScore"] as? Double,
              let weeklyGrade = enhancedAnalysisDict["weeklyGrade"] as? String
        else { return nil }
        
        // Parse hijack frequency data
        let hijackData = enhancedAnalysisDict["hijackFrequency"] as? [String: Any]
        let totalHijacks = hijackData?["totalHijacks"] as? Int ?? 0
        let interventionRate = hijackData?["interventionSuccessRate"] as? Double ?? 0.0
        
        // Parse emotional trends
        let emotionalData = enhancedAnalysisDict["emotionalTrends"] as? [String: Any]
        let moodStability = emotionalData?["moodStability"] as? Double ?? 0.0
        
        // Parse progress markers
        let progressData = enhancedAnalysisDict["progressMarkers"] as? [String: Any]
        let agencyRatio = progressData?["agencyRatio"] as? Double ?? 0.0
        
        // Parse ritual effectiveness
        let ritualData = enhancedAnalysisDict["ritualEffectiveness"] as? [String: Any]
        let avgReliefLevel = ritualData?["averageReliefLevel"] as? Double ?? 0.0
        
        // Parse trigger patterns
        let triggerData = enhancedAnalysisDict["triggerPatterns"] as? [String: Any]
        let topTriggersDict = triggerData?["topTriggers"] as? [String: Int] ?? [:]
        let dominantTriggers = Array(topTriggersDict.keys.prefix(3))
        
        // Parse unspoken needs
        let needsData = enhancedAnalysisDict["unspokenNeeds"] as? [String: Any]
        let inferredNeedsDict = needsData?["inferredNeeds"] as? [String: Double] ?? [:]
        let topNeeds = Array(inferredNeedsDict.keys.prefix(3))
        
        // Calculate week number from date
        let calendar = Calendar.current
        let weekOfYear = calendar.component(.weekOfYear, from: createdAt.dateValue())
        
        return ProgressSnapshot(
            weekNumber: weekOfYear,
            date: createdAt.dateValue(),
            integrationScore: integrationScore,
            hijackFrequency: totalHijacks,
            recoveryRate: interventionRate,
            moodStability: moodStability,
            agencyRatio: agencyRatio,
            ritualEffectiveness: avgReliefLevel,
            dominantTriggers: dominantTriggers,
            topNeeds: topNeeds,
            weeklyGrade: weeklyGrade
        )
    }
}

// MARK: - Goal Types
enum GoalType: String, CaseIterable {
    case calmingRitual = "calming_ritual"
    case bedRitual = "bed_ritual"
    case brainDump = "brain_dump"
    case hijackRitual = "hijack_ritual"
    
    var title: String {
        switch self {
        case .calmingRitual: return "Daily Calm"
        case .bedRitual: return "Sleep Ritual"
        case .brainDump: return "Brain Dump"
        case .hijackRitual: return "Hijack Recovery"
        }
    }
    
    var description: String {
        switch self {
        case .calmingRitual: return "Complete your calming ritual"
        case .bedRitual: return "Prepare for restful sleep"
        case .brainDump: return "Clear your mental space"
        case .hijackRitual: return "Recover from hijack incident"
        }
    }
    
    var icon: String {
        switch self {
        case .calmingRitual: return "heart.fill"
        case .bedRitual: return "moon.fill"
        case .brainDump: return "brain.head.profile"
        case .hijackRitual: return "arrow.clockwise"
        }
    }
    
    var color: Color {
        switch self {
        case .calmingRitual: return .green
        case .bedRitual: return .indigo
        case .brainDump: return .red
        case .hijackRitual: return .orange
        }
    }
}

enum GoalStatus {
    case completed
    case pending
    case warning
    case urgent
}

struct DailyGoal {
    let type: GoalType
    let status: GoalStatus
    let message: String
    let priority: Int
}

// MARK: - Streak Tier System
enum StreakTier: String {
    case beginner = "beginner"
    case building = "building"
    case consistent = "consistent"
    case master = "master"
    case legendary = "legendary"
}

extension StreakTier: Comparable {
    static func < (lhs: StreakTier, rhs: StreakTier) -> Bool {
        return lhs.order < rhs.order
    }

    private var order: Int {
        switch self {
        case .beginner: return 0
        case .building: return 1
        case .consistent: return 2
        case .master: return 3
        case .legendary: return 4
        }
    }
}

// MARK: - Data Models
struct ActionCardData {
    let icon: String
    let title: String
    let subtitle: String
    let color: Color
    let action: String
}


// MARK: - Enhanced ShadowDashboardView with Historical Analytics
struct EnhancedShadowDashboardView: View {
    @StateObject private var mapModel = ShadowMapModel()
    @StateObject private var journalModel = JournalEntryModel()
    @StateObject private var historicalAnalytics = HistoricalAnalyticsManager()
    @EnvironmentObject var analysisManager: WeeklyAnalysisManager
    
    // Navigation states
    @State private var showLoggingSheet = false
    @State private var showMapModal = false
    @State private var showBrainDump = false
    @State private var showWeeklyInsights = false
    @State private var selectedLogType: LogType = .hijack
    
    // Modern animation states
    @State private var fadeIn = false
    @State private var pulseAnimation = false
    @State private var progressAnimation: Double = 0.0
    @State private var cardsStagger: [Bool] = Array(repeating: false, count: 15)
    @State private var subtleGlow = false
    @State private var showHistoricalView = false
    
    // UI state for integration metrics
    @State private var displayedRitualDays: Int = 0
    @State private var displayedConversionScore: Double = 0.0
    @State private var displayedStreak: Int = 0
    @State private var displayedIntegrationPercentage: Double = 0.0
    
    var onTabChange: ((Int) -> Void)?
    
    // Integration calculation constants
    private let ritualDayTarget = 60
    private let maxStreakDays = 365
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Modern clean background
                modernBackground
                
                // Main content
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 20)
                        
                        // Enhanced dashboard header with historical insights
                        enhancedDashboardHeader
                            .opacity(fadeIn ? 1 : 0)
                            .animation(.spring(response: 1.2, dampingFraction: 0.8).delay(0.2), value: fadeIn)
                        
                        Spacer(minLength: 32)
                        
                        // Historical progress overview
                        if !historicalAnalytics.progressSnapshots.isEmpty {
                            historicalProgressSection
                                .opacity(fadeIn ? 1 : 0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.3), value: fadeIn)
                            
                            Spacer(minLength: 32)
                        }
                        
                        // Enhanced integration section
                        enhancedIntegrationSection
                            .opacity(fadeIn ? 1 : 0)
                            .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.4), value: fadeIn)
                        
                        Spacer(minLength: 32)
                        
                        // Trend analysis section
                        if let trendData = historicalAnalytics.trendData {
                            trendAnalysisSection(trendData)
                                .opacity(fadeIn ? 1 : 0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.5), value: fadeIn)
                            
                            Spacer(minLength: 32)
                        }
                        
                        // Historical charts section
                        if historicalAnalytics.progressSnapshots.count >= 3 {
                            historicalChartsSection
                                .opacity(fadeIn ? 1 : 0)
                                .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.6), value: fadeIn)
                            
                            Spacer(minLength: 32)
                        }
                        
                        // Today's goals (simplified from original)
                        simplifiedTodaysGoals
                            .opacity(fadeIn ? 1 : 0)
                            .animation(.spring(response: 1.0, dampingFraction: 0.8).delay(0.7), value: fadeIn)
                        
                        Spacer(minLength: 32)
                        
                        // Action cards with historical context
                        enhancedActionCards
                        
                        Spacer(minLength: 120)
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .onAppear {
            startModernAnimations()
            mapModel.loadShadowEntries()
            journalModel.fetchLastDumpDate()
            updateDisplayedValues()
            
            // Load historical data
            historicalAnalytics.loadHistoricalData()
            
            analysisManager.checkForBrainDumps()
            analysisManager.checkForPendingAnalysis()
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            updateDisplayedValues()
        }
        .onChange(of: mapModel.shadowEntries) { _ in
            updateDisplayedValues()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                progressAnimation = displayedIntegrationPercentage
            }
            analysisManager.checkForPendingAnalysis()
        }
        .sheet(isPresented: $showMapModal) {
            ModernShadowMapModalView(mapModel: mapModel)
        }
        .sheet(isPresented: $showBrainDump) {
            ShadowBrainDumpView(model: journalModel)
        }
        .sheet(isPresented: $showWeeklyInsights) {
            if let current = analysisManager.currentAnalysis {
                WeeklyInsightsView()
            }
        }
    }
    
    // MARK: - Enhanced Dashboard Components
    
    var enhancedDashboardHeader: some View {
        VStack(spacing: 24) {
            // Clean app icon with historical context
            ZStack {
                // Subtle backdrop
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.08),
                                Color.white.opacity(0.04)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
                
                // Enhanced icon with progress indicator
                ZStack {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.cyan, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            }
            .scaleEffect(pulseAnimation ? 1.02 : 1.0)
            .animation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true), value: pulseAnimation)
            
            // Enhanced typography with insights
            VStack(spacing: 8) {
                Text("Dashboard")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color.white, Color.white.opacity(0.8)],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                
                if let trendData = historicalAnalytics.trendData {
                    Text(trendInsightText(trendData))
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                } else {
                    Text("Track your daily progress and maintain momentum")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
            }
        }
    }
    
    var historicalProgressSection: some View {
        VStack(spacing: 20) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Progress Journey")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(historicalAnalytics.progressSnapshots.count) weeks of data")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Trend indicator
                if let trendData = historicalAnalytics.trendData {
                    HStack(spacing: 6) {
                        Image(systemName: trendIcon(for: trendData.improvementTrend))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(trendColor(for: trendData.improvementTrend))
                        
                        Text(trendDirection(for: trendData.improvementTrend))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundColor(trendColor(for: trendData.improvementTrend))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(trendColor(for: trendData.improvementTrend).opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(trendColor(for: trendData.improvementTrend).opacity(0.3), lineWidth: 1)
                            )
                    )
                }
            }
            
            // Weekly progress snapshots (last 6 weeks)
            if historicalAnalytics.progressSnapshots.count >= 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(historicalAnalytics.progressSnapshots.suffix(6).enumerated()), id: \.offset) { index, snapshot in
                            weeklyProgressCard(snapshot: snapshot, isLatest: index == historicalAnalytics.progressSnapshots.suffix(6).count - 1)
                        }
                    }
                    .padding(.horizontal, 20)
                }
            }
        }
        .scaleEffect(cardsStagger[safe: 0] ?? false ? 1 : 0.95)
        .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.2), value: cardsStagger[safe: 0] ?? false)
    }
    
    func weeklyProgressCard(snapshot: ProgressSnapshot, isLatest: Bool) -> some View {
        VStack(spacing: 8) {
            // Week indicator
            Text("W\(snapshot.weekNumber)")
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
            
            // Score circle
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 2)
                    .frame(width: 36, height: 36)
                
                Circle()
                    .trim(from: 0, to: snapshot.integrationScore / 100)
                    .stroke(scoreColor(for: snapshot.integrationScore), lineWidth: 2)
                    .frame(width: 36, height: 36)
                    .rotationEffect(.degrees(-90))
                
                Text("\(Int(snapshot.integrationScore))")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            // Grade
            Text(snapshot.weeklyGrade)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(gradeColor(for: snapshot.weeklyGrade))
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 60)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isLatest ? Color.white.opacity(0.08) : Color.white.opacity(0.04))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(
                            isLatest ? Color.blue.opacity(0.3) : Color.white.opacity(0.1),
                            lineWidth: isLatest ? 1.5 : 1
                        )
                )
        )
        .scaleEffect(isLatest ? 1.05 : 1.0)
    }
    
    var enhancedIntegrationSection: some View {
        VStack(spacing: 24) {
            // Integration Card with historical context
            VStack(spacing: 24) {
                // Header with comparison
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Integration Score")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        if let comparison = weekOverWeekComparison() {
                            Text(comparison)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(comparison.contains("↑") ? .green : comparison.contains("↓") ? .red : .orange)
                        } else {
                            Text("Your overall progress today")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    
                    Spacer()
                    
                    // Enhanced score badge with prediction
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Text("\(Int(displayedIntegrationPercentage * 100))%")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                            
                            Image(systemName: displayedIntegrationPercentage >= 0.8 ? "arrow.up.circle.fill" :
                                  displayedIntegrationPercentage >= 0.5 ? "minus.circle.fill" : "arrow.down.circle.fill")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(
                                    displayedIntegrationPercentage >= 0.8 ? .green :
                                    displayedIntegrationPercentage >= 0.5 ? .orange : .red
                                )
                        }
                        
                        if let trendData = historicalAnalytics.trendData {
                            Text("Proj: \(Int(trendData.projectedScore))%")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20)
                                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
                            )
                    )
                }
                
                // Enhanced Progress Visualization
                VStack(spacing: 16) {
                    // Main progress bar
                    ZStack(alignment: .leading) {
                        // Background
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.08))
                            .frame(height: 8)
                        
                        // Progress
                        RoundedRectangle(cornerRadius: 12)
                            .fill(
                                LinearGradient(
                                    colors: progressGradientColors,
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(8, progressAnimation * (UIScreen.main.bounds.width - 88)), height: 8)
                            .animation(.easeInOut(duration: 2.0).delay(0.5), value: progressAnimation)
                    }
                    
                    // Enhanced Progress segments with historical context
                    HStack(spacing: 12) {
                        enhancedIntegrationMetric(
                            title: "Ritual Days",
                            value: "\(displayedRitualDays)/\(ritualDayTarget)",
                            percentage: Double(displayedRitualDays) / Double(ritualDayTarget),
                            color: .green,
                            historicalAverage: historicalAverage(for: \.ritualEffectiveness)
                        )
                        
                        enhancedIntegrationMetric(
                            title: "Recovery",
                            value: totalHijackDays > 0 ? "\(Int((Double(hijacksWithRituals) / Double(totalHijackDays)) * 100))%" : "0%",
                            percentage: totalHijackDays > 0 ? Double(hijacksWithRituals) / Double(totalHijackDays) : 0.0,
                            color: .orange,
                            historicalAverage: historicalAverage(for: \.recoveryRate)
                        )
                        
                        enhancedIntegrationMetric(
                            title: "Streak",
                            value: "\(displayedStreak) days",
                            percentage: min(1.0, Double(displayedStreak) / Double(maxStreakDays)),
                            color: .purple,
                            historicalAverage: nil // Streak doesn't have historical average
                        )
                    }
                }
            }
            .padding(24)
            .background(modernCardBackground)
            
            // Enhanced Streak Display with historical context
            enhancedStreakDisplay
        }
    }
    
    func trendAnalysisSection(_ trendData: TrendData) -> some View {
        VStack(spacing: 20) {
            // Section header
            HStack {
                Text("Trend Analysis")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
                
                // Consistency score
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                    
                    Text("\(Int(trendData.consistencyScore * 100))% consistent")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.green)
                }
            }
            
            // Trend cards
            HStack(spacing: 16) {
                // Improvement trend card
                trendCard(
                    title: "Progress Trend",
                    value: trendPercentageText(trendData.improvementTrend),
                    icon: trendIcon(for: trendData.improvementTrend),
                    color: trendColor(for: trendData.improvementTrend),
                    subtitle: trendDirection(for: trendData.improvementTrend)
                )
                
                // Best performing area
                trendCard(
                    title: "Strongest Area",
                    value: trendData.bestMetric,
                    icon: "crown.fill",
                    color: .green,
                    subtitle: "Keep it up!"
                )
            }
            
            HStack(spacing: 16) {
                // Focus area
                trendCard(
                    title: "Focus Area",
                    value: trendData.focusArea,
                    icon: "target",
                    color: .orange,
                    subtitle: "Needs attention"
                )
                
                // Prediction
                trendCard(
                    title: "Next Week",
                    value: "\(Int(trendData.projectedScore))%",
                    icon: "target",
                    color: .purple,
                    subtitle: "Projected score"
                )
            }
        }
        .scaleEffect(cardsStagger[safe: 1] ?? false ? 1 : 0.95)
        .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.3), value: cardsStagger[safe: 1] ?? false)
    }
    
    func trendCard(title: String, value: String, icon: String, color: Color, subtitle: String) -> some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(color)
                
                Spacer()
                
                Text(title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .tracking(1)
            }
            
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            
            Text(subtitle)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.6))
                .lineLimit(1)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 80)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [
                            color.opacity(0.1),
                            color.opacity(0.05)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(color.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: color.opacity(0.1), radius: 4, x: 0, y: 2)
        )
    }
    
    var historicalChartsSection: some View {
        VStack(spacing: 20) {
            // Section header
            HStack {
                Text("Historical Charts")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                // Integration score trend chart
                if historicalAnalytics.progressSnapshots.count >= 3 {
                    integrationTrendChart
                        .padding(20)
                        .background(modernCardBackground)
                }
                
                // Metrics comparison chart
                if historicalAnalytics.progressSnapshots.count >= 3 {
                    metricsComparisonChart
                        .padding(20)
                        .background(modernCardBackground)
                }
            }
        }
        .scaleEffect(cardsStagger[safe: 2] ?? false ? 1 : 0.95)
        .animation(.spring(response: 0.8, dampingFraction: 0.8).delay(0.4), value: cardsStagger[safe: 2] ?? false)
    }
    
    var integrationTrendChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Integration Score Trend")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            Chart(historicalAnalytics.progressSnapshots, id: \.weekNumber) { snapshot in
                LineMark(
                    x: .value("Week", "W\(snapshot.weekNumber)"),
                    y: .value("Score", snapshot.integrationScore)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan, .blue],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                
                AreaMark(
                    x: .value("Week", "W\(snapshot.weekNumber)"),
                    yStart: .value("Zero", 0),
                    yEnd: .value("Score", snapshot.integrationScore)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [.cyan.opacity(0.3), .clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                
                PointMark(
                    x: .value("Week", "W\(snapshot.weekNumber)"),
                    y: .value("Score", snapshot.integrationScore)
                )
                .foregroundStyle(.white)
                .symbolSize(30)
            }
            .chartYScale(domain: 0...100)
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                        .foregroundStyle(.white.opacity(0.1))
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .chartXAxis {
                AxisMarks(position: .bottom) { _ in
                    AxisValueLabel()
                        .foregroundStyle(.white.opacity(0.8))
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .frame(height: 150)
        }
    }
    
    var metricsComparisonChart: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Key Metrics Comparison")
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
            
            if let latest = historicalAnalytics.progressSnapshots.last,
               let previous = historicalAnalytics.progressSnapshots.dropLast().last {
                
                VStack(spacing: 12) {
                    metricComparisonRow(
                        title: "Recovery Rate",
                        current: latest.recoveryRate,
                        previous: previous.recoveryRate,
                        color: .orange,
                        suffix: "%"
                    )
                    
                    metricComparisonRow(
                        title: "Mood Stability",
                        current: latest.moodStability,
                        previous: previous.moodStability,
                        color: .purple,
                        suffix: "%"
                    )
                    
                    metricComparisonRow(
                        title: "Agency Ratio",
                        current: latest.agencyRatio * 100,
                        previous: previous.agencyRatio * 100,
                        color: .green,
                        suffix: "%"
                    )
                }
            }
        }
    }
    
    func metricComparisonRow(title: String, current: Double, previous: Double, color: Color, suffix: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.white.opacity(0.8))
            
            Spacer()
            
            HStack(spacing: 8) {
                Text("\(Int(current))\(suffix)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                
                let change = current - previous
                HStack(spacing: 2) {
                    Image(systemName: change > 0 ? "arrow.up" : change < 0 ? "arrow.down" : "minus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(change > 0 ? .green : change < 0 ? .red : .orange)
                    
                    Text("\(Int(abs(change)))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(change > 0 ? .green : change < 0 ? .red : .orange)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill((change > 0 ? Color.green : change < 0 ? Color.red : Color.orange).opacity(0.2))
                )
            }
        }
        .padding(.vertical, 4)
    }
    
    // Enhanced integration metric with historical context
    func enhancedIntegrationMetric(title: String, value: String, percentage: Double, color: Color, historicalAverage: Double?) -> some View {
        VStack(spacing: 8) {
            // Mini progress ring
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 2)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .trim(from: 0, to: percentage)
                    .stroke(color, lineWidth: 2)
                    .frame(width: 32, height: 32)
                    .rotationEffect(.degrees(-90))
                
                // Historical average indicator
                if let average = historicalAverage {
                    Circle()
                        .trim(from: 0, to: 0.02) // Small indicator
                        .stroke(Color.white.opacity(0.6), lineWidth: 1)
                        .frame(width: 36, height: 36)
                        .rotationEffect(.degrees(-90 + (average / 100 * 360)))
                }
                
                Text("\(Int(percentage * 100))%")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }
            
            VStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                
                Text(value)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                // Historical comparison
                if let average = historicalAverage {
                    let comparison = (percentage * 100) - average
                    Text(comparison > 0 ? "+\(Int(comparison))" : "\(Int(comparison))")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundColor(comparison > 0 ? .green : comparison < 0 ? .red : .orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }
    
    var enhancedStreakDisplay: some View {
        HStack(spacing: 16) {
            // Streak icon with modern styling
            ZStack {
                RoundedRectangle(cornerRadius: 16)
                    .fill(streakModernBackground)
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(streakBorderColor, lineWidth: 1.5)
                    )
                
                Image(systemName: streakIcon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(streakIconGradient)
            }
            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true), value: pulseAnimation)
            
            // Enhanced streak info with historical context
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("\(displayedStreak)")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(streakTextGradient)
                    
                    Text("day streak")
                        .font(.system(size: 16, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.8))
                    
                    // Personal best indicator
                    if let personalBest = personalBestStreak(), displayedStreak == personalBest {
                        Text("PB!")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(.yellow.opacity(0.2))
                            )
                    }
                }
                
                HStack(spacing: 8) {
                    Text(streakStatusText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                    
                    // Average streak comparison
                    if let avgStreak = averageStreakLength() {
                        Text("Avg: \(avgStreak) days")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
            
            Spacer()
            
            // Enhanced tier badge
            if streakTier != .beginner {
                VStack(spacing: 4) {
                    tierBadge
                    
                    // Days to next tier
                    if let daysToNext = daysToNextTier() {
                        Text("\(daysToNext) to next")
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }
        }
        .padding(20)
        .background(modernCardBackground)
    }
    
    var simplifiedTodaysGoals: some View {
        VStack(spacing: 20) {
            // Section header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's Goals")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(completedGoalsCount) of \(dailyGoals.count) completed")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                }
                
                Spacer()
                
                // Progress indicator
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.1), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    
                    Circle()
                        .trim(from: 0, to: dailyGoals.isEmpty ? 0 : Double(completedGoalsCount) / Double(dailyGoals.count))
                        .stroke(Color.green, lineWidth: 3)
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                    
                    Text("\(dailyGoals.isEmpty ? 0 : Int((Double(completedGoalsCount) / Double(dailyGoals.count)) * 100))")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                }
            }
            
            // Goals grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 16) {
                ForEach(Array(dailyGoals.enumerated()), id: \.offset) { index, goal in
                    simplifiedGoalCard(goal: goal, index: index)
                        .opacity(cardsStagger[safe: index + 3] ?? false ? 1 : 0)
                        .offset(y: cardsStagger[safe: index + 3] ?? false ? 0 : 20)
                        .scaleEffect(cardsStagger[safe: index + 3] ?? false ? 1 : 0.95)
                        .animation(
                            .spring(response: 0.8, dampingFraction: 0.8)
                            .delay(Double(index) * 0.1 + 0.8),
                            value: cardsStagger[safe: index + 3] ?? false
                        )
                }
            }
        }
    }
    
    var enhancedActionCards: some View {
        VStack(spacing: 20) {
            // Section header
            HStack {
                Text("Quick Actions")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
                
                Spacer()
            }
            
            VStack(spacing: 16) {
                
                // Historical insights card
                if historicalAnalytics.progressSnapshots.count >= 3 {
                    historicalInsightsCard
                        .opacity(cardsStagger[safe: 11] ?? false ? 1 : 0)
                        .offset(y: cardsStagger[safe: 11] ?? false ? 0 : 20)
                        .scaleEffect(cardsStagger[safe: 11] ?? false ? 1 : 0.95)
                        .animation(
                            .spring(response: 0.8, dampingFraction: 0.8)
                            .delay(1.5),
                            value: cardsStagger[safe: 11] ?? false
                        )
                }
                
                // Regular action cards
                ForEach(Array(actionCardData.enumerated()), id: \.offset) { index, card in
                    simplifiedActionCard(card: card)
                        .opacity(cardsStagger[safe: index + 12] ?? false ? 1 : 0)
                        .offset(y: cardsStagger[safe: index + 12] ?? false ? 0 : 20)
                        .scaleEffect(cardsStagger[safe: index + 12] ?? false ? 1 : 0.95)
                        .animation(
                            .spring(response: 0.8, dampingFraction: 0.8)
                            .delay(Double(index) * 0.1 + 1.6),
                            value: cardsStagger[safe: index + 12] ?? false
                        )
                }
            }
        }
    }
    
    var enhancedAnalysisCard: some View {
        Button(action: {
            handleSimplifiedActionTap(action: "analysis")
        }) {
            HStack(spacing: 16) {
                // Enhanced analysis icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.red.opacity(0.2),
                                    Color.orange.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                    
                    Image(systemName: "brain.head.profile.fill")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.red, Color.orange],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    
                    // Available indicator with historical context
                    Circle()
                        .fill(Color.green)
                        .frame(width: 12, height: 12)
                        .offset(x: 20, y: -20)
                        .scaleEffect(subtleGlow ? 1.2 : 1.0)
                        .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: subtleGlow)
                }
                
                // Enhanced content
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text("Shadow Analysis")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                        
                        Text("NEW")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.green)
                            )
                    }
                    
                    let weekNumber = historicalAnalytics.progressSnapshots.count + 1
                    Text("Week \(weekNumber) insights are ready")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
            .background(modernCardBackground)
        }
    }
    
    var historicalInsightsCard: some View {
        Button(action: {
            showHistoricalView = true
        }) {
            HStack(spacing: 16) {
                // Historical insights icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.purple.opacity(0.2),
                                    Color.indigo.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                        )
                    
                    Image(systemName: "chart.xyaxis.line")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [Color.purple, Color.indigo],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text("Historical Insights")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text("\(historicalAnalytics.progressSnapshots.count) weeks of progress data")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
            .background(modernCardBackground)
        }
    }
    
    // MARK: - Goal Card Components
    
    func simplifiedGoalCard(goal: DailyGoal, index: Int) -> some View {
        let action = {
            handleSimplifiedGoalTap(goal: goal)
        }

        return Button(action: action) {
            VStack(spacing: 16) {
                goalCardHeader(goal: goal, subtleGlow: subtleGlow)
                goalCardContent(goal: goal)
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(goal.status == .completed ? 0.04 : 0.06))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(
                                goal.status == .urgent ? Color.red.opacity(0.3) :
                                goal.status == .warning ? Color.orange.opacity(0.3) :
                                Color.white.opacity(0.1),
                                lineWidth: goal.status == .urgent ? 1.5 : 1
                            )
                    )
            )
        }
    }
    
    @ViewBuilder
    func goalCardHeader(goal: DailyGoal, subtleGlow: Bool) -> some View {
        HStack {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(goal.type.color.opacity(goal.status == .completed ? 0.2 : 0.1))
                    .frame(width: 40, height: 40)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(goal.type.color.opacity(goal.status == .completed ? 0.4 : 0.3), lineWidth: 1)
                    )

                if goal.status == .completed {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                } else {
                    Image(systemName: goal.type.icon)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(goal.type.color)
                }
            }

            Spacer()

            if goal.status == .urgent || goal.status == .warning {
                Circle()
                    .fill(goal.status == .urgent ? .red : .orange)
                    .frame(width: 8, height: 8)
                    .scaleEffect(subtleGlow ? 1.2 : 1.0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: subtleGlow)
            }
        }
    }

    @ViewBuilder
    func goalCardContent(goal: DailyGoal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(goal.type.title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white.opacity(goal.status == .completed ? 0.7 : 0.9))
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(goal.message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(
                    goal.status == .urgent ? .red.opacity(0.8) :
                    goal.status == .warning ? .orange.opacity(0.8) :
                    .white.opacity(0.6)
                )
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    
    let actionCardData = [
        ActionCardData(
            icon: "map.fill",
            title: "Encounter Calendar",
            subtitle: "View your transformation journey",
            color: .cyan,
            action: "map"
        ),
        ActionCardData(
            icon: "brain.head.profile",
            title: "Brain Dump",
            subtitle: "Clear your mental space",
            color: .red,
            action: "dump"
        )
    ]
    
    func simplifiedActionCard(card: ActionCardData) -> some View {
        Button(action: {
            handleSimplifiedActionTap(action: card.action)
        }) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(
                            LinearGradient(
                                colors: [
                                    card.color.opacity(0.2),
                                    card.color.opacity(0.1)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 56, height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .stroke(card.color.opacity(0.3), lineWidth: 1)
                        )
                    
                    Image(systemName: card.icon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [card.color, card.color.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
                
                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                    
                    Text(card.subtitle)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7))
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.4))
            }
            .padding(20)
            .background(modernCardBackground)
        }
    }
    
    // MARK: - Visual Properties and Styling
    
    var modernBackground: some View {
        ZStack {
            // Clean gradient background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.02, green: 0.02, blue: 0.08),
                    Color.black
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            
            // Subtle overlay texture
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.03),
                    Color.clear,
                    Color.purple.opacity(0.02)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
        }
    }
    
    var modernCardBackground: some View {
        RoundedRectangle(cornerRadius: 20)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.06),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(
                        LinearGradient(
                            colors: [
                                Color.white.opacity(0.15),
                                Color.white.opacity(0.05)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .shadow(
                color: Color.black.opacity(0.1),
                radius: 10,
                x: 0,
                y: 5
            )
    }
    
    var progressGradientColors: [Color] {
        if displayedIntegrationPercentage >= 0.8 {
            return [Color.green.opacity(0.8), Color.cyan]
        } else if displayedIntegrationPercentage >= 0.5 {
            return [Color.orange.opacity(0.8), Color.yellow]
        } else {
            return [Color.red.opacity(0.8), Color.pink]
        }
    }
    
    // MARK: - Streak Properties
    var streakTier: StreakTier {
        switch displayedStreak {
        case 0...6: return .beginner
        case 7...13: return .building
        case 14...29: return .consistent
        case 30...59: return .master
        default: return .legendary
        }
    }
    
    var streakModernBackground: LinearGradient {
        switch streakTier {
        case .beginner:
            return LinearGradient(colors: [Color.gray.opacity(0.2), Color.gray.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .building:
            return LinearGradient(colors: [Color.orange.opacity(0.2), Color.orange.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .consistent:
            return LinearGradient(colors: [Color.purple.opacity(0.2), Color.purple.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .master:
            return LinearGradient(colors: [Color.blue.opacity(0.2), Color.blue.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)
        case .legendary:
            return LinearGradient(colors: [Color.yellow.opacity(0.3), Color.orange.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }
    
    var streakBorderColor: Color {
        switch streakTier {
        case .beginner: return Color.gray.opacity(0.3)
        case .building: return Color.orange.opacity(0.4)
        case .consistent: return Color.purple.opacity(0.4)
        case .master: return Color.blue.opacity(0.4)
        case .legendary: return Color.yellow.opacity(0.6)
        }
    }
    
    var streakIcon: String {
        switch streakTier {
        case .beginner: return "flame"
        case .building: return "flame.fill"
        case .consistent: return "star"
        case .master: return "star.fill"
        case .legendary: return "crown.fill"
        }
    }
    
    var streakTextGradient: LinearGradient {
        switch streakTier {
        case .beginner:
            return LinearGradient(colors: [Color.white, Color.gray.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
        case .building:
            return LinearGradient(colors: [Color.orange, Color.red], startPoint: .leading, endPoint: .trailing)
        case .consistent:
            return LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .leading, endPoint: .trailing)
        case .master:
            return LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .leading, endPoint: .trailing)
        case .legendary:
            return LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .leading, endPoint: .trailing)
        }
    }
    
    var streakIconGradient: LinearGradient {
        switch streakTier {
        case .beginner:
            return LinearGradient(colors: [Color.gray, Color.white], startPoint: .top, endPoint: .bottom)
        case .building:
            return LinearGradient(colors: [Color.orange, Color.red], startPoint: .top, endPoint: .bottom)
        case .consistent:
            return LinearGradient(colors: [Color.purple, Color.indigo], startPoint: .top, endPoint: .bottom)
        case .master:
            return LinearGradient(colors: [Color.blue, Color.cyan], startPoint: .top, endPoint: .bottom)
        case .legendary:
            return LinearGradient(colors: [Color.yellow, Color.orange], startPoint: .top, endPoint: .bottom)
        }
    }
    
    var streakStatusText: String {
        switch streakTier {
        case .beginner: return "Just getting started"
        case .building: return "Building momentum"
        case .consistent: return "Staying consistent"
        case .master: return "Master level"
        case .legendary: return "Legendary status"
        }
    }
    
    var tierBadge: some View {
        Text(streakTier.rawValue.capitalized)
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(streakBorderColor)
            )
    }
    
    // MARK: - Helper Functions for Historical Data
    
    private func trendInsightText(_ trendData: TrendData) -> String {
        if trendData.improvementTrend > 0.3 {
            return "Strong upward trajectory this month"
        } else if trendData.improvementTrend > 0.1 {
            return "Steady progress over recent weeks"
        } else if trendData.improvementTrend > -0.1 {
            return "Maintaining stable integration levels"
        } else {
            return "Focus needed to regain momentum"
        }
    }
    
    private func weekOverWeekComparison() -> String? {
        guard historicalAnalytics.progressSnapshots.count >= 2 else { return nil }
        
        let latest = historicalAnalytics.progressSnapshots.last!.integrationScore
        let previous = historicalAnalytics.progressSnapshots.dropLast().last!.integrationScore
        let change = latest - previous
        
        if abs(change) < 2 {
            return "Stable from last week"
        } else if change > 0 {
            return "↑ \(Int(change)) points from last week"
        } else {
            return "↓ \(Int(abs(change))) points from last week"
        }
    }
    
    private func historicalAverage(for keyPath: KeyPath<ProgressSnapshot, Double>) -> Double? {
        guard !historicalAnalytics.progressSnapshots.isEmpty else { return nil }
        
        let values = historicalAnalytics.progressSnapshots.map { $0[keyPath: keyPath] }
        return values.reduce(0, +) / Double(values.count)
    }
    
    private func personalBestStreak() -> Int? {
        // This would need to be implemented based on your streak tracking
        // For now, return nil as we don't have historical streak data in the snapshots
        return nil
    }
    
    private func averageStreakLength() -> Int? {
        // This would also need historical streak data
        return nil
    }
    
    private func daysToNextTier() -> Int? {
        switch streakTier {
        case .beginner: return max(0, 7 - displayedStreak)
        case .building: return max(0, 14 - displayedStreak)
        case .consistent: return max(0, 30 - displayedStreak)
        case .master: return max(0, 60 - displayedStreak)
        case .legendary: return nil
        }
    }
    
    private func trendIcon(for trend: Double) -> String {
        if trend > 0.2 { return "arrow.up.circle.fill" }
        else if trend > 0 { return "arrow.up.right.circle.fill" }
        else if trend > -0.2 { return "minus.circle.fill" }
        else { return "arrow.down.circle.fill" }
    }
    
    private func trendColor(for trend: Double) -> Color {
        if trend > 0.1 { return .green }
        else if trend > -0.1 { return .orange }
        else { return .red }
    }
    
    private func trendDirection(for trend: Double) -> String {
        if trend > 0.2 { return "Strong Growth" }
        else if trend > 0.1 { return "Improving" }
        else if trend > -0.1 { return "Stable" }
        else { return "Declining" }
    }
    
    private func trendPercentageText(_ trend: Double) -> String {
        let percentage = Int(abs(trend * 100))
        return trend >= 0 ? "+\(percentage)%" : "-\(percentage)%"
    }
    
    private func scoreColor(for score: Double) -> Color {
        if score >= 80 { return .green }
        else if score >= 60 { return .orange }
        else { return .red }
    }
    
    private func gradeColor(for grade: String) -> Color {
        switch grade {
        case "A": return .green
        case "B": return .cyan
        case "C": return .orange
        case "D": return .red
        case "F": return .red
        default: return .white
        }
    }
    
    // MARK: - Action Handlers
    
    private func handleSimplifiedGoalTap(goal: DailyGoal) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        switch goal.type {
        case .brainDump:
            if goal.status != .completed {
                showBrainDump = true
            }
        case .calmingRitual:
            if goal.status != .completed {
                onTabChange?(2)
            }
        case .bedRitual:
            if goal.status != .completed {
                selectedLogType = .ritual
                showLoggingSheet = true
            }
        case .hijackRitual:
            if goal.status != .completed {
                onTabChange?(2)
            }
        }
    }
    
    private func handleSimplifiedActionTap(action: String) {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
        
        switch action {
        case "map":
            showMapModal = true
        case "dump":
            showBrainDump = true
        case "analysis":
            showWeeklyInsights = true
            analysisManager.markAnalysisAsRead()
        default:
            break
        }
    }
    
    // MARK: - Calculations
    var integrationPercentage: Double {
        return (ritualDayScore * 0.5) + (conversionScore * 0.3) + (streakScore * 0.2)
    }
    
    var ritualDayScore: Double {
        let days = ritualDaysThisMonth
        let score = Double(days) / Double(ritualDayTarget)
        return min(1.0, score)
    }
    
    var conversionScore: Double {
        guard totalHijackDays > 0 else { return 0.0 }
        return Double(hijacksWithRituals) / Double(totalHijackDays)
    }
    
    var streakScore: Double {
        return min(1.0, Double(currentStreak) / Double(maxStreakDays))
    }
    
    var ritualDaysThisMonth: Int {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let recentEntries = mapModel.shadowEntries.filter { $0.timestamp >= thirtyDaysAgo }
        let groupedByDay = Dictionary(grouping: recentEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        var fullRitualDays = 0
        
        for (_, dayEntries) in groupedByDay {
            let hijacks = dayEntries.filter { $0.logType == .hijack }
            let hijackRituals = dayEntries.filter {
                $0.logType == .ritual && $0.ritualTiming == "hijack"
            }
            let calmingRituals = dayEntries.filter {
                $0.logType == .ritual && $0.ritualTiming == "calming"
            }
            let beforeBedRituals = dayEntries.filter {
                $0.logType == .ritual && $0.ritualTiming == "before bed"
            }
            
            let hasHijackCombo = hijacks.count > 0 && hijackRituals.count > 0
            let hasCalmingCombo = calmingRituals.count > 0 && beforeBedRituals.count > 0
            
            if hasHijackCombo || hasCalmingCombo {
                fullRitualDays += 1
            }
        }
        
        return fullRitualDays
    }
    
    var currentStreak: Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let entries = mapModel.shadowEntries.sorted { $0.timestamp > $1.timestamp }
        let groupedByDay = Dictionary(grouping: entries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }

        var streak = 0
        var currentDate = today

        // Check if today has fulfilled ritual criteria
        let todayEntries = groupedByDay[today] ?? []
        let hasHijack = todayEntries.contains { $0.logType == .hijack }
        let hasHijackRitual = todayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "hijack" }
        let hasCalmingRitual = todayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "calming" }
        let hasBeforeBedRitual = todayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "before bed" }
        let todayComplete = (hasHijack && hasHijackRitual) || (hasCalmingRitual && hasBeforeBedRitual)

        if !todayComplete {
            currentDate = calendar.date(byAdding: .day, value: -1, to: today)!
        }

        while true {
            guard let dayEntries = groupedByDay[currentDate] else { break }

            let hasHijack = dayEntries.contains { $0.logType == .hijack }
            let hasHijackRitual = dayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "hijack" }
            let hasCalmingRitual = dayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "calming" }
            let hasBeforeBedRitual = dayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "before bed" }

            if (hasHijack && hasHijackRitual) || (hasCalmingRitual && hasBeforeBedRitual) {
                streak += 1
                currentDate = calendar.date(byAdding: .day, value: -1, to: currentDate)!
            } else {
                break
            }
        }

        return streak
    }
    
    var totalHijackDays: Int {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let hijackEntries = mapModel.shadowEntries.filter {
            $0.logType == .hijack && $0.timestamp >= thirtyDaysAgo
        }
        
        let uniqueDays = Set(hijackEntries.map { calendar.startOfDay(for: $0.timestamp) })
        return uniqueDays.count
    }
    
    var hijacksWithRituals: Int {
        let calendar = Calendar.current
        let thirtyDaysAgo = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        let recentEntries = mapModel.shadowEntries.filter { $0.timestamp >= thirtyDaysAgo }
        let groupedByDay = Dictionary(grouping: recentEntries) { entry in
            calendar.startOfDay(for: entry.timestamp)
        }
        
        var daysWithBoth = 0
        
        for (_, dayEntries) in groupedByDay {
            let hasHijack = dayEntries.contains { $0.logType == .hijack }
            let hasHijackRitual = dayEntries.contains {
                $0.logType == .ritual && $0.ritualTiming == "hijack"
            }
            
            if hasHijack && hasHijackRitual {
                daysWithBoth += 1
            }
        }
        
        return daysWithBoth
    }
    
    var dailyGoals: [DailyGoal] {
        var goals: [DailyGoal] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        
        let todayEntries = mapModel.shadowEntries.filter {
            calendar.startOfDay(for: $0.timestamp) == today
        }
        
        // Brain dump goal
        let canDump = journalModel.canSave
        let hasDumpedToday = !canDump && journalModel.lastDumpDate != nil &&
        calendar.isDate(journalModel.lastDumpDate!, inSameDayAs: Date())
        
        if hasDumpedToday {
            goals.append(DailyGoal(
                type: .brainDump,
                status: .completed,
                message: "Mental space cleared",
                priority: 1
            ))
        } else if canDump {
            goals.append(DailyGoal(
                type: .brainDump,
                status: .pending,
                message: "Clear your thoughts",
                priority: 2
            ))
        }
        
        // Calming ritual goal
        let hasCalmingRitual = todayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "calming" }
        goals.append(DailyGoal(
            type: .calmingRitual,
            status: hasCalmingRitual ? .completed : .pending,
            message: hasCalmingRitual ? "Inner peace achieved" : "Find your center today",
            priority: hasCalmingRitual ? 4 : 3
        ))
        
        // Before bed ritual goal
        let hasBeforeBedRitual = todayEntries.contains { $0.logType == .ritual && $0.ritualTiming == "before bed" }
        let isEvening = Calendar.current.component(.hour, from: Date()) >= 18
        
        goals.append(DailyGoal(
            type: .bedRitual,
            status: hasBeforeBedRitual ? .completed : (isEvening ? .pending : .pending),
            message: hasBeforeBedRitual ? "Ready for restful sleep" : (isEvening ? "Prepare for sleep" : "Evening ritual awaits"),
            priority: hasBeforeBedRitual ? 4 : (isEvening ? 2 : 3)
        ))
        
        // Hijack ritual goal
        let hijackCount = todayEntries.filter { $0.logType == .hijack }.count
        let hijackRitualCount = todayEntries.filter {
            $0.logType == .ritual && $0.ritualTiming == "hijack"
        }.count
        
        if hijackCount > 0 {
            let isFullyRecovered = hijackRitualCount >= hijackCount
            let remainingHijacks = max(0, hijackCount - hijackRitualCount)
            
            goals.append(DailyGoal(
                type: .hijackRitual,
                status: isFullyRecovered ? .completed : .urgent,
                message: isFullyRecovered ?
                "All hijacks recovered." :
                "Recover from \(remainingHijacks) hijack\(remainingHijacks == 1 ? "" : "s")",
                priority: isFullyRecovered ? 4 : 0
            ))
        }
        
        return goals.sorted { $0.priority < $1.priority }
    }
    
    var completedGoalsCount: Int {
        dailyGoals.filter { $0.status == .completed }.count
    }
    
    private func updateDisplayedValues() {
        displayedRitualDays = ritualDaysThisMonth
        displayedStreak = currentStreak
        
        let ritualScore = Double(displayedRitualDays) / Double(ritualDayTarget)
        let conversionScore = totalHijackDays > 0 ? Double(hijacksWithRituals) / Double(totalHijackDays) : 0.0
        let streakScore = min(1.0, Double(displayedStreak) / Double(maxStreakDays))
        
        displayedIntegrationPercentage = (ritualScore * 0.5) + (conversionScore * 0.3) + (streakScore * 0.2)
    }
    
    // MARK: - Animation Functions
    private func startModernAnimations() {
        withAnimation(.easeOut(duration: 1.2)) {
            fadeIn = true
        }
        
        // Progress animation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            progressAnimation = displayedIntegrationPercentage
        }
        
        // Stagger card animations
        for i in 0..<cardsStagger.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.1 + 1.0) {
                cardsStagger[i] = true
            }
        }
        
        // Subtle continuous animations
        withAnimation(.easeInOut(duration: 4.0).repeatForever(autoreverses: true)) {
            pulseAnimation = true
        }
        
        withAnimation(.easeInOut(duration: 3.0).repeatForever(autoreverses: true).delay(0.5)) {
            subtleGlow = true
        }
    }
}

extension Array {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}
