package score

// CountedPercent is the share of base points a day needs to count toward the streak.
const CountedPercent = 70

// QuestPoints is the base credit for a quest: points scaled by progress, rounded half up, in
// integers only.
func QuestPoints(points, actual, target int) int {
	if target <= 0 || actual <= 0 {
		return 0
	}
	return (points*min(actual, target) + target/2) / target
}

// Bonus is the extra credit for completing a quest.
func Bonus(points int) int { return points / 5 }

// The reading quest's exchange rates are a round rule Nick and Nadia chose: a page for each
// minute of reading, and an audiobook minute worth half a reading minute, so 30 pages is 30
// minutes of reading or 60 of listening. Research sits close to it (Brysbaert 2019: adults read
// about 238 words a minute, about a 250-word page a minute; narrators speak about 155 a minute,
// two thirds of that), and the rule rounds it to numbers anyone can check in their head.
const (
	PagesPerReadingMinute            = 1
	ListeningMinutesPerReadingMinute = 2
)

// PagesForMinutes is the pages that match minutes of reading, never below one so a short
// target still has a pages way to finish it.
func PagesForMinutes(minutes int) int { return max(1, minutes*PagesPerReadingMinute) }

// ListeningCredit is the reading minutes that minutes of audiobook listening are worth. It rounds
// down so a fraction of a minute never earns a minute.
func ListeningCredit(listening int) int { return max(listening, 0) / ListeningMinutesPerReadingMinute }

// ReadingMinutes is the minutes the reading quest sees: minutes typed in plus the listening
// credit. Pages are not touched.
func ReadingMinutes(manual, listening int) int { return manual + ListeningCredit(listening) }

// ReadingProgressBasis expresses p = min(1, minutes/targetMinutes + pages/targetPages) as an
// integer pair for QuestPoints: multiplying through by targetMinutes*targetPages makes the
// sum of two fractions exact.
func ReadingProgressBasis(minutes, pages, targetMinutes, targetPages int) (actual, target int) {
	return minutes*targetPages + pages*targetMinutes, targetMinutes * targetPages
}

// QuestResult is one active quest with how far the user got. Actual and Target share a unit,
// which for reading is the basis from ReadingProgressBasis.
type QuestResult struct {
	Key    string `json:"key"`
	Points int    `json:"points"`
	Actual int    `json:"actual"`
	Target int    `json:"target"`
}

// QuestScore is a QuestResult with its credit worked out.
type QuestScore struct {
	QuestResult
	Base     int  `json:"base"`
	Bonus    int  `json:"bonus"`
	Complete bool `json:"complete"`
}

// DayScore is the outcome of one day. Percent and Counted use base points only, so the bonus
// never changes whether a day counts.
type DayScore struct {
	BasePoints  int          `json:"basePoints"`
	BonusPoints int          `json:"bonusPoints"`
	MaxBase     int          `json:"maxBase"`
	Percent     int          `json:"percent"`
	Counted     bool         `json:"counted"`
	Quests      []QuestScore `json:"quests"`
}

// ScoreDay totals a day. A day with no active quests has nothing to count.
func ScoreDay(quests []QuestResult) DayScore {
	score := DayScore{Quests: make([]QuestScore, 0, len(quests))}
	for _, q := range quests {
		qs := QuestScore{
			QuestResult: q,
			Base:        QuestPoints(q.Points, q.Actual, q.Target),
			Complete:    q.Target > 0 && q.Actual >= q.Target,
		}
		if qs.Complete {
			qs.Bonus = Bonus(q.Points)
		}
		score.BasePoints += qs.Base
		score.BonusPoints += qs.Bonus
		score.MaxBase += q.Points
		score.Quests = append(score.Quests, qs)
	}
	if score.MaxBase > 0 {
		score.Percent = min(100, score.BasePoints*100/score.MaxBase)
		score.Counted = score.BasePoints*100 >= CountedPercent*score.MaxBase
	}
	return score
}

// GoalPoints is the base points a day needs to count: CountedPercent of the possible base points,
// rounded up.
func GoalPoints(maxBase int) int {
	if maxBase <= 0 {
		return 0
	}
	return (maxBase*CountedPercent + 99) / 100
}

// GoalPercent is the share of the day's goal that the base points reached. A day counts exactly
// when it is 100 or more, and it can go above 100 when more than the goal is earned.
func GoalPercent(base, maxBase int) int {
	goal := GoalPoints(maxBase)
	if goal <= 0 || base <= 0 {
		return 0
	}
	return base * 100 / goal
}
