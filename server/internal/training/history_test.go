package training

import (
	"reflect"
	"testing"
)

func TestChartSeries(t *testing.T) {
	tests := []struct {
		name          string
		holds, loaded bool
		sets          []Set
		metric        Metric
		points        []Point
	}{
		{"e1rm takes each day's best of 1-10 rep sets", false, true,
			[]Set{{Date: "2026-10-01", Reps: 5, LoadKg: 60}, {Date: "2026-10-01", Reps: 8, LoadKg: 60},
				{Date: "2026-10-03", Reps: 1, LoadKg: 90}, {Date: "2026-10-02", Reps: 12, LoadKg: 40}},
			MetricE1RM, []Point{{"2026-10-01", 76}, {"2026-10-03", 90}}},
		{"high reps chart volume load", false, true,
			[]Set{{Date: "2026-10-02", Reps: 12, LoadKg: 40}, {Date: "2026-10-02", Reps: 15, LoadKg: 20},
				{Date: "2026-10-01", Reps: 11, LoadKg: 22.5}},
			MetricVolume, []Point{{"2026-10-01", 247.5}, {"2026-10-02", 480}}},
		{"bodyweight charts best reps", false, false,
			[]Set{{Date: "2026-10-02", Reps: 9}, {Date: "2026-10-02", Reps: 12}, {Date: "2026-10-01", Reps: 7}},
			MetricReps, []Point{{"2026-10-01", 7}, {"2026-10-02", 12}}},
		{"holds chart best seconds", true, false,
			[]Set{{Date: "2026-10-01", Seconds: 30}, {Date: "2026-10-01", Seconds: 45}},
			MetricSeconds, []Point{{"2026-10-01", 45}}},
		{"unloaded sets of a loaded exercise are skipped", false, true,
			[]Set{{Date: "2026-10-01", Reps: 8}}, MetricVolume, []Point{}},
		{"no sets", false, true, nil, MetricVolume, []Point{}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := ChartSeries(tt.holds, tt.loaded, tt.sets)
			if got.Metric != tt.metric || !reflect.DeepEqual(got.Points, tt.points) {
				t.Fatalf("got %v %v, want %v %v", got.Metric, got.Points, tt.metric, tt.points)
			}
		})
	}
}

func TestOnlyE1RMIsEstimated(t *testing.T) {
	if !MetricE1RM.Estimated() || MetricVolume.Estimated() || MetricReps.Estimated() || MetricSeconds.Estimated() {
		t.Fatal("only the one-rep-max metric is an estimate")
	}
}
