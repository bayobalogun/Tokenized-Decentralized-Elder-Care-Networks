;; Family Communication Contract
;; Facilitates regular updates to relatives

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_INPUT (err u102))
(define-constant ERR_ALREADY_EXISTS (err u103))

;; Data Variables
(define-data-var next-update-id uint u1)
(define-data-var next-schedule-id uint u1)

;; Data Maps
(define-map family-members
  { participant-id: uint, family-member: principal }
  {
    name: (string-ascii 50),
    relationship: (string-ascii 30),
    contact-info: (string-ascii 100),
    access-level: uint,
    notification-preferences: (string-ascii 100),
    active: bool,
    last-contact: (optional uint)
  }
)

(define-map health-updates
  { update-id: uint }
  {
    participant-id: uint,
    update-type: (string-ascii 30),
    title: (string-ascii 100),
    content: (string-ascii 500),
    timestamp: uint,
    privacy-level: uint,
    verified: bool,
    verification-source: (optional principal)
  }
)

(define-map communication-schedules
  { schedule-id: uint }
  {
    participant-id: uint,
    family-member: principal,
    frequency: uint,
    preferred-time: uint,
    communication-type: (string-ascii 30),
    last-communication: (optional uint),
    next-scheduled: uint,
    active: bool
  }
)

(define-map update-access
  { update-id: uint, family-member: principal }
  {
    can-view: bool,
    viewed: bool,
    view-timestamp: (optional uint),
    response: (string-ascii 200)
  }
)

(define-map communication-logs
  { participant-id: uint, family-member: principal, timestamp: uint }
  {
    communication-type: (string-ascii 30),
    duration: uint,
    quality-rating: (optional uint),
    notes: (string-ascii 300),
    initiated-by: principal
  }
)

(define-map participant-profiles
  { participant-id: uint }
  {
    address: principal,
    name: (string-ascii 50),
    communication-preferences: (string-ascii 200),
    privacy-settings: uint,
    tokens-earned: uint,
    total-updates: uint,
    active: bool
  }
)

(define-map update-reminders
  { participant-id: uint, reminder-type: (string-ascii 30) }
  {
    frequency: uint,
    last-reminder: uint,
    next-reminder: uint,
    enabled: bool,
    custom-message: (string-ascii 200)
  }
)

;; Participant Management Functions
(define-public (register-communication-participant (participant-id uint) (name (string-ascii 50)) (communication-preferences (string-ascii 200)) (privacy-settings uint))
  (begin
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)
    (asserts! (<= privacy-settings u3) ERR_INVALID_INPUT)

    (map-set participant-profiles
      { participant-id: participant-id }
      {
        address: tx-sender,
        name: name,
        communication-preferences: communication-preferences,
        privacy-settings: privacy-settings,
        tokens-earned: u0,
        total-updates: u0,
        active: true
      }
    )
    (ok true)
  )
)

(define-public (add-family-member (participant-id uint) (family-member principal) (name (string-ascii 50)) (relationship (string-ascii 30)) (contact-info (string-ascii 100)) (access-level uint) (notification-preferences (string-ascii 100)))
  (begin
    (asserts! (is-some (map-get? participant-profiles { participant-id: participant-id })) ERR_NOT_FOUND)
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)
    (asserts! (> (len relationship) u0) ERR_INVALID_INPUT)
    (asserts! (<= access-level u3) ERR_INVALID_INPUT)

    (map-set family-members
      { participant-id: participant-id, family-member: family-member }
      {
        name: name,
        relationship: relationship,
        contact-info: contact-info,
        access-level: access-level,
        notification-preferences: notification-preferences,
        active: true,
        last-contact: none
      }
    )
    (ok true)
  )
)

;; Update Management Functions
(define-public (post-health-update (participant-id uint) (update-type (string-ascii 30)) (title (string-ascii 100)) (content (string-ascii 500)) (privacy-level uint))
  (let ((update-id (var-get next-update-id)))
    (asserts! (is-some (map-get? participant-profiles { participant-id: participant-id })) ERR_NOT_FOUND)
    (asserts! (> (len update-type) u0) ERR_INVALID_INPUT)
    (asserts! (> (len title) u0) ERR_INVALID_INPUT)
    (asserts! (> (len content) u0) ERR_INVALID_INPUT)
    (asserts! (<= privacy-level u3) ERR_INVALID_INPUT)

    (map-set health-updates
      { update-id: update-id }
      {
        participant-id: participant-id,
        update-type: update-type,
        title: title,
        content: content,
        timestamp: block-height,
        privacy-level: privacy-level,
        verified: false,
        verification-source: none
      }
    )
    (var-set next-update-id (+ update-id u1))

    ;; Grant access to family members based on privacy level
    (unwrap-panic (grant-family-access update-id participant-id privacy-level))

    ;; Reward for posting update
    (unwrap-panic (reward-communication-activity participant-id u10))

    (ok update-id)
  )
)

(define-public (verify-health-update (update-id uint))
  (match (map-get? health-updates { update-id: update-id })
    update-data
    (begin
      ;; Only healthcare providers or authorized personnel can verify
      (map-set health-updates
        { update-id: update-id }
        (merge update-data {
          verified: true,
          verification-source: (some tx-sender)
        })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Communication Scheduling Functions
(define-public (create-communication-schedule (participant-id uint) (family-member principal) (frequency uint) (preferred-time uint) (communication-type (string-ascii 30)))
  (let ((schedule-id (var-get next-schedule-id)))
    (asserts! (is-some (map-get? family-members { participant-id: participant-id, family-member: family-member })) ERR_NOT_FOUND)
    (asserts! (> frequency u0) ERR_INVALID_INPUT)
    (asserts! (> (len communication-type) u0) ERR_INVALID_INPUT)

    (map-set communication-schedules
      { schedule-id: schedule-id }
      {
        participant-id: participant-id,
        family-member: family-member,
        frequency: frequency,
        preferred-time: preferred-time,
        communication-type: communication-type,
        last-communication: none,
        next-scheduled: (+ block-height frequency),
        active: true
      }
    )
    (var-set next-schedule-id (+ schedule-id u1))
    (ok schedule-id)
  )
)

(define-public (log-communication (participant-id uint) (family-member principal) (communication-type (string-ascii 30)) (duration uint) (quality-rating uint) (notes (string-ascii 300)))
  (begin
    (asserts! (is-some (map-get? family-members { participant-id: participant-id, family-member: family-member })) ERR_NOT_FOUND)
    (asserts! (> (len communication-type) u0) ERR_INVALID_INPUT)
    (asserts! (and (>= quality-rating u1) (<= quality-rating u5)) ERR_INVALID_INPUT)

    (map-set communication-logs
      { participant-id: participant-id, family-member: family-member, timestamp: block-height }
      {
        communication-type: communication-type,
        duration: duration,
        quality-rating: (some quality-rating),
        notes: notes,
        initiated-by: tx-sender
      }
    )

    ;; Update last contact time
    (try! (update-last-contact participant-id family-member))

    ;; Reward for communication
    (try! (reward-communication-activity participant-id u5))

    (ok true)
  )
)

;; Access Control Functions
(define-public (view-health-update (update-id uint))
  (match (map-get? update-access { update-id: update-id, family-member: tx-sender })
    access-data
    (begin
      (asserts! (get can-view access-data) ERR_UNAUTHORIZED)
      (map-set update-access
        { update-id: update-id, family-member: tx-sender }
        (merge access-data {
          viewed: true,
          view-timestamp: (some block-height)
        })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

(define-public (respond-to-update (update-id uint) (response (string-ascii 200)))
  (match (map-get? update-access { update-id: update-id, family-member: tx-sender })
    access-data
    (begin
      (asserts! (get can-view access-data) ERR_UNAUTHORIZED)
      (asserts! (> (len response) u0) ERR_INVALID_INPUT)

      (map-set update-access
        { update-id: update-id, family-member: tx-sender }
        (merge access-data { response: response })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Reminder System Functions
(define-public (set-update-reminder (participant-id uint) (reminder-type (string-ascii 30)) (frequency uint) (custom-message (string-ascii 200)))
  (begin
    (asserts! (is-some (map-get? participant-profiles { participant-id: participant-id })) ERR_NOT_FOUND)
    (asserts! (> (len reminder-type) u0) ERR_INVALID_INPUT)
    (asserts! (> frequency u0) ERR_INVALID_INPUT)

    (map-set update-reminders
      { participant-id: participant-id, reminder-type: reminder-type }
      {
        frequency: frequency,
        last-reminder: block-height,
        next-reminder: (+ block-height frequency),
        enabled: true,
        custom-message: custom-message
      }
    )
    (ok true)
  )
)

;; Helper Functions
(define-private (grant-family-access (update-id uint) (participant-id uint) (privacy-level uint))
  ;; Simplified access granting - would iterate through family members in real implementation
  (ok true)
)

(define-private (update-last-contact (participant-id uint) (family-member principal))
  (match (map-get? family-members { participant-id: participant-id, family-member: family-member })
    member-data
    (begin
      (map-set family-members
        { participant-id: participant-id, family-member: family-member }
        (merge member-data { last-contact: (some block-height) })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

(define-private (reward-communication-activity (participant-id uint) (tokens uint))
  (match (map-get? participant-profiles { participant-id: participant-id })
    profile-data
    (begin
      (map-set participant-profiles
        { participant-id: participant-id }
        (merge profile-data {
          tokens-earned: (+ (get tokens-earned profile-data) tokens),
          total-updates: (+ (get total-updates profile-data) u1)
        })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Read-only Functions
(define-read-only (get-participant-profile (participant-id uint))
  (map-get? participant-profiles { participant-id: participant-id })
)

(define-read-only (get-family-member (participant-id uint) (family-member principal))
  (map-get? family-members { participant-id: participant-id, family-member: family-member })
)

(define-read-only (get-health-update (update-id uint))
  (map-get? health-updates { update-id: update-id })
)

(define-read-only (get-communication-schedule (schedule-id uint))
  (map-get? communication-schedules { schedule-id: schedule-id })
)

(define-read-only (get-update-access (update-id uint) (family-member principal))
  (map-get? update-access { update-id: update-id, family-member: family-member })
)

(define-read-only (get-communication-log (participant-id uint) (family-member principal) (timestamp uint))
  (map-get? communication-logs { participant-id: participant-id, family-member: family-member, timestamp: timestamp })
)

(define-read-only (get-update-reminder (participant-id uint) (reminder-type (string-ascii 30)))
  (map-get? update-reminders { participant-id: participant-id, reminder-type: reminder-type })
)

(define-read-only (get-participant-tokens (participant-id uint))
  (match (map-get? participant-profiles { participant-id: participant-id })
    profile-data (some (get tokens-earned profile-data))
    none
  )
)
