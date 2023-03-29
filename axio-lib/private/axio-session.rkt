#lang racket/base

(require "./axio-config.rkt"
         "./axio-serialize.rkt"
         "./axio-web-ctx.rkt")

(require (only-in net/cookies/server cookie?)
         db
         gregor
         gregor/period
         net/uri-codec
         racket/contract
         racket/string
         web-server/http
         web-server/http/id-cookie)

(provide (contract-out
          [ clear-flash
            (-> hash? any) ]
          [ create-session-cookie
            (-> hash? cookie?) ]
          [ deserialize-session
            (-> string? hash?) ]
          [ flash-set
            (-> webctx? symbol? string? any) ]
          [ get-flash
            (-> webctx? (or/c hash? #f)) ]
          [ get-session
            (-> request? connection? any) ]
          [ serialize-session
            (-> hash? string?) ]
          [ session-get
            (-> webctx? symbol? (or/c string? #f)) ]
          [ session-remove
            (-> webctx? symbol? webctx?) ]
          [ session-set
            (-> webctx? symbol? string? webctx?) ]))

(define thirty-days-seconds (* 30 24 60 60))

;; --------------------------------------------------------------------------------------------
;; Public Interface
;; --------------------------------------------------------------------------------------------

(define (clear-flash session)
  (hash-remove session 'flash))

(define (create-session-cookie session)
  (make-id-cookie "session"
                  (serialize-session session)
                  #:key (axio-config-app-secret a-axio-config)
                  #:path "/"
                ; #:secure #t  ; requires https
                  #:max-age (+ thirty-days-seconds (seconds-until-midnight))
                  #:http-only? #t))

(define (deserialize-session str)
  (let ([ result (and str
                      (non-empty-string? str)
                      (let ([ obj (deserialize (uri-decode str)) ])
                        (if (and obj
                                 (hash? obj))
                            obj
                            #f))) ])
    (or result (hash))))

(define (flash-set ctx key val)
  (let* ([ flash-hsh (hash-ref (webctx-session ctx)
                               'flash
                               #f) ])
    (session-set ctx
                 'flash
                 (if flash-hsh
                     (hash-set flash-hsh key val)
                     (hash key val)))))

(define (get-flash ctx)
  (let* ([ session (webctx-session ctx)                       ]
         [ flash   (and session (hash-ref session 'flash #f)) ])
    flash))

(define (get-session request conn)
  ;; Only cookie session is supported currently, but we'll add database sessions later
  (get-cookie-session request))

(define (serialize-session session)
  (uri-encode (serialize session)))

(define (session-get ctx key)
  (let ([ session (webctx-session ctx) ])
    (if session
        (hash-ref session key #f)
        #f)))

(define (session-remove ctx key)
  (struct-copy webctx
               ctx
               [ session (hash-remove (webctx-session ctx)
                                      key) ]))

(define (session-set ctx key val)
  (struct-copy webctx
               ctx
               [ session (hash-set (webctx-session ctx)
                                   key
                                   val) ]))

;; --------------------------------------------------------------------------------------------
;; Private helpers
;; --------------------------------------------------------------------------------------------

; (-> request? (or/c hash? #f))
(define (get-cookie-session request)
  (deserialize-session (request-id-cookie
                        request
                        #:name "session"
                        #:shelf-life thirty-days-seconds
                        #:key (axio-config-app-secret a-axio-config))))

(define (seconds-until-midnight)
  (let* ([ t1    (now)                                  ]
         [ t2    (at-midnight (today))                  ]
         [ delta (time-period-between t1 t2 '(seconds)) ])
    (+ (period-ref delta 'seconds) 86400)))
