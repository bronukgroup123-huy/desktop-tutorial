import { create } from "zustand";
import type {
  GuardianSession,
  GuardianSessionResponse,
  TrackPoint,
} from "@/lib/types";

interface GuardianState {
  session: GuardianSession | null;
  derived: GuardianSessionResponse["derived"] | null;
  guardians: GuardianSessionResponse["guardians"];
  track: TrackPoint[];
  currentGuardianId: string | null;
  loading: boolean;
  error: string | null;
  lastUpdateAt: number | null;
  setSession: (data: GuardianSessionResponse) => void;
  setTrack: (points: TrackPoint[]) => void;
  appendTrackPoint: (point: TrackPoint) => void;
  setLoading: (loading: boolean) => void;
  setError: (error: string | null) => void;
  reset: () => void;
}

export const useGuardianStore = create<GuardianState>((set) => ({
  session: null,
  derived: null,
  guardians: [],
  track: [],
  currentGuardianId: null,
  loading: true,
  error: null,
  lastUpdateAt: null,

  setSession: (data) =>
    set({
      session: data.session,
      derived: data.derived,
      guardians: data.guardians,
      currentGuardianId: data.current_guardian_id,
      loading: false,
      error: null,
      lastUpdateAt: Date.now(),
    }),

  setTrack: (points) => set({ track: points }),

  appendTrackPoint: (point) =>
    set((state) => {
      const last = state.track[state.track.length - 1];
      if (last && last.recorded_at === point.recorded_at) return state;
      return { track: [...state.track, point] };
    }),

  setLoading: (loading) => set({ loading }),
  setError: (error) => set({ error, loading: false }),
  reset: () =>
    set({
      session: null,
      derived: null,
      guardians: [],
      track: [],
      currentGuardianId: null,
      loading: true,
      error: null,
      lastUpdateAt: null,
    }),
}));
