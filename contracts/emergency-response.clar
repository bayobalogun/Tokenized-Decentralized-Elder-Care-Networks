;; Emergency Response Contract
;; Provides rapid assistance during medical crises

;; Constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_INVALID_INPUT (err u102))
(define-constant ERR_ALREADY_EXISTS (err u103))

;; Data Variables
(define-data-var next-emergency-id uint u1)
(define-data-var next-responder-id uint u1)

;; Data Maps
(define-map emergency-alerts
  { emergency-id: uint }
  {
    participant-id: uint,
    alert-type: (string-ascii 30),
    severity: uint,
    location: (string-ascii 100),
    timestamp: uint,
    status: (string-ascii 20),
    assigned-responder: (optional principal),
    response-time: (optional uint),
    resolution-time: (optional uint),
    notes: (string-ascii 500)
  }
)

(define-map emergency-responders
  { responder-id: uint }
  {
    address: principal,
    name: (string-ascii 50),
    certification: (string-ascii 50),
    specialization: (string-ascii 50),
    availability: bool,
    response-count: uint,
    average-response-time: uint,
    rating: uint,
    tokens-earned: uint
  }
)

(define-map emergency-contacts
  { participant-id: uint, contact-type: (string-ascii 20) }
  {
    contact-address: principal,
    name: (string-ascii 50),
    phone: (string-ascii 20),
    relationship: (string-ascii 30),
    priority: uint,
    active: bool
  }
)

(define-map response-assignments
  { emergency-id: uint, responder: principal }
  {
    assigned-time: uint,
    accepted-time: (optional uint),
    arrival-time: (optional uint),
    completion-time: (optional uint),
    status: (string-ascii 20)
  }
)

(define-map emergency-participants
  { participant-id: uint }
  {
    address: principal,
    name: (string-ascii 50),
    medical-conditions: (string-ascii 200),
    medications: (string-ascii 200),
    emergency-plan: (string-ascii 300),
    active: bool
  }
)

;; Emergency Alert Functions
(define-public (create-emergency-alert (participant-id uint) (alert-type (string-ascii 30)) (severity uint) (location (string-ascii 100)) (notes (string-ascii 500)))
  (let ((emergency-id (var-get next-emergency-id)))
    (asserts! (> (len alert-type) u0) ERR_INVALID_INPUT)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR_INVALID_INPUT)
    (asserts! (> (len location) u0) ERR_INVALID_INPUT)

    (map-set emergency-alerts
      { emergency-id: emergency-id }
      {
        participant-id: participant-id,
        alert-type: alert-type,
        severity: severity,
        location: location,
        timestamp: block-height,
        status: "ACTIVE",
        assigned-responder: none,
        response-time: none,
        resolution-time: none,
        notes: notes
      }
    )
    (var-set next-emergency-id (+ emergency-id u1))

    ;; Auto-assign responder based on severity
    (if (>= severity u4)
      (unwrap-panic (auto-assign-responder emergency-id))
      true
    )

    (ok emergency-id)
  )
)

(define-public (register-emergency-responder (name (string-ascii 50)) (certification (string-ascii 50)) (specialization (string-ascii 50)))
  (let ((responder-id (var-get next-responder-id)))
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)
    (asserts! (> (len certification) u0) ERR_INVALID_INPUT)

    (map-set emergency-responders
      { responder-id: responder-id }
      {
        address: tx-sender,
        name: name,
        certification: certification,
        specialization: specialization,
        availability: true,
        response-count: u0,
        average-response-time: u0,
        rating: u5,
        tokens-earned: u0
      }
    )
    (var-set next-responder-id (+ responder-id u1))
    (ok responder-id)
  )
)

(define-public (register-emergency-participant (participant-id uint) (name (string-ascii 50)) (medical-conditions (string-ascii 200)) (medications (string-ascii 200)) (emergency-plan (string-ascii 300)))
  (begin
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)

    (map-set emergency-participants
      { participant-id: participant-id }
      {
        address: tx-sender,
        name: name,
        medical-conditions: medical-conditions,
        medications: medications,
        emergency-plan: emergency-plan,
        active: true
      }
    )
    (ok true)
  )
)

;; Response Management Functions
(define-public (assign-responder (emergency-id uint) (responder principal))
  (match (map-get? emergency-alerts { emergency-id: emergency-id })
    alert-data
    (begin
      (asserts! (is-eq (get status alert-data) "ACTIVE") ERR_INVALID_INPUT)
      (map-set emergency-alerts
        { emergency-id: emergency-id }
        (merge alert-data {
          assigned-responder: (some responder),
          status: "ASSIGNED"
        })
      )
      (map-set response-assignments
        { emergency-id: emergency-id, responder: responder }
        {
          assigned-time: block-height,
          accepted-time: none,
          arrival-time: none,
          completion-time: none,
          status: "ASSIGNED"
        }
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

(define-public (accept-emergency-response (emergency-id uint))
  (match (map-get? response-assignments { emergency-id: emergency-id, responder: tx-sender })
    assignment-data
    (begin
      (asserts! (is-eq (get status assignment-data) "ASSIGNED") ERR_INVALID_INPUT)
      (map-set response-assignments
        { emergency-id: emergency-id, responder: tx-sender }
        (merge assignment-data {
          accepted-time: (some block-height),
          status: "ACCEPTED"
        })
      )
      (try! (update-emergency-status emergency-id "IN_PROGRESS"))
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

(define-public (report-arrival (emergency-id uint))
  (match (map-get? response-assignments { emergency-id: emergency-id, responder: tx-sender })
    assignment-data
    (begin
      (asserts! (is-eq (get status assignment-data) "ACCEPTED") ERR_INVALID_INPUT)
      (map-set response-assignments
        { emergency-id: emergency-id, responder: tx-sender }
        (merge assignment-data {
          arrival-time: (some block-height),
          status: "ON_SCENE"
        })
      )
      (try! (calculate-response-time emergency-id))
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

(define-public (complete-emergency-response (emergency-id uint) (resolution-notes (string-ascii 500)))
  (match (map-get? response-assignments { emergency-id: emergency-id, responder: tx-sender })
    assignment-data
    (begin
      (asserts! (is-eq (get status assignment-data) "ON_SCENE") ERR_INVALID_INPUT)
      (map-set response-assignments
        { emergency-id: emergency-id, responder: tx-sender }
        (merge assignment-data {
          completion-time: (some block-height),
          status: "COMPLETED"
        })
      )
      (try! (update-emergency-status emergency-id "RESOLVED"))
      (try! (reward-responder tx-sender emergency-id))
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Emergency Contact Management
(define-public (add-emergency-contact (participant-id uint) (contact-type (string-ascii 20)) (contact-address principal) (name (string-ascii 50)) (phone (string-ascii 20)) (relationship (string-ascii 30)) (priority uint))
  (begin
    (asserts! (> (len contact-type) u0) ERR_INVALID_INPUT)
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)
    (asserts! (> priority u0) ERR_INVALID_INPUT)

    (map-set emergency-contacts
      { participant-id: participant-id, contact-type: contact-type }
      {
        contact-address: contact-address,
        name: name,
        phone: phone,
        relationship: relationship,
        priority: priority,
        active: true
      }
    )
    (ok true)
  )
)

;; Helper Functions
(define-private (auto-assign-responder (emergency-id uint))
  ;; Simplified auto-assignment logic
  ;; In a real implementation, this would find the best available responder
  (ok true)
)

(define-private (update-emergency-status (emergency-id uint) (new-status (string-ascii 20)))
  (match (map-get? emergency-alerts { emergency-id: emergency-id })
    alert-data
    (begin
      (map-set emergency-alerts
        { emergency-id: emergency-id }
        (merge alert-data { status: new-status })
      )
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

(define-private (calculate-response-time (emergency-id uint))
  (match (map-get? emergency-alerts { emergency-id: emergency-id })
    alert-data
    (match (map-get? response-assignments { emergency-id: emergency-id, responder: tx-sender })
      assignment-data
      (let ((response-time (- block-height (get timestamp alert-data))))
        (map-set emergency-alerts
          { emergency-id: emergency-id }
          (merge alert-data { response-time: (some response-time) })
        )
        (ok true)
      )
      ERR_NOT_FOUND
    )
    ERR_NOT_FOUND
  )
)

(define-private (reward-responder (responder principal) (emergency-id uint))
  (match (map-get? emergency-alerts { emergency-id: emergency-id })
    alert-data
    (let ((reward-amount (if (>= (get severity alert-data) u4) u50 u25)))
      ;; Update responder tokens and stats
      ;; This is a simplified implementation
      (ok true)
    )
    ERR_NOT_FOUND
  )
)

;; Availability Management
(define-public (set-availability (available bool))
  ;; Find and update responder availability
  ;; Simplified implementation
  (ok true)
)

;; Read-only Functions
(define-read-only (get-emergency-alert (emergency-id uint))
  (map-get? emergency-alerts { emergency-id: emergency-id })
)

(define-read-only (get-emergency-responder (responder-id uint))
  (map-get? emergency-responders { responder-id: responder-id })
)

(define-read-only (get-emergency-contact (participant-id uint) (contact-type (string-ascii 20)))
  (map-get? emergency-contacts { participant-id: participant-id, contact-type: contact-type })
)

(define-read-only (get-response-assignment (emergency-id uint) (responder principal))
  (map-get? response-assignments { emergency-id: emergency-id, responder: responder })
)

(define-read-only (get-emergency-participant (participant-id uint))
  (map-get? emergency-participants { participant-id: participant-id })
)

(define-read-only (get-active-emergencies-count)
  ;; This would require iteration in a real implementation
  u0
)
