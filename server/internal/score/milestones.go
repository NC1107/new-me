package score

// StreakMilestones are the streak lengths, in days, that are celebrated once.
var StreakMilestones = []int{7, 14, 30, 50, 100, 200, 365}

// MilestonesReached lists the milestones a streak of the given length has reached, in order.
func MilestonesReached(current int) []int {
	var out []int
	for _, m := range StreakMilestones {
		if current >= m {
			out = append(out, m)
		}
	}
	return out
}

// TenKSteps is the step count of the first-10k milestone.
const TenKSteps = 10000
