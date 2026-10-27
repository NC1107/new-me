package score

// Season is a scoring period; EndsOn is nil for the open-ended current one.
type Season struct {
	ID       int64
	Name     string
	StartsOn Date
	EndsOn   *Date
}

// Contains reports whether the date falls inside the season.
func (s Season) Contains(d Date) bool {
	return !d.Before(s.StartsOn) && (s.EndsOn == nil || !d.After(*s.EndsOn))
}

// WeekRange is the Monday-start week holding date, clipped to the season so a week that
// straddles a season boundary only shows the days that belong to it.
func (s Season) WeekRange(date Date) (from, to Date) {
	from = WeekStart(date)
	to = from.AddDays(6)
	if from.Before(s.StartsOn) {
		from = s.StartsOn
	}
	if s.EndsOn != nil && to.After(*s.EndsOn) {
		to = *s.EndsOn
	}
	return from, to
}

// SeasonFor finds the season a local date belongs to.
func SeasonFor(date Date, seasons []Season) (Season, bool) {
	for _, s := range seasons {
		if s.Contains(date) {
			return s, true
		}
	}
	return Season{}, false
}
