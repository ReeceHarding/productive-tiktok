import SwiftUI
import EventKit

// Re-export types needed by the Calendar feature
@_exported import class EventKit.EKEventStore
@_exported import class EventKit.EKEvent

// No typealiases needed since we're in the same module 