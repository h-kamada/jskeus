;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;
;;; $Id: $
;;;
;;; Copyright (c) 1987- JSK, The University of Tokyo.  All Rights Reserved.
;;;
;;; This software is a collection of EusLisp code for robot applications,
;;; which has been developed by the JSK Laboratory for the IRT project.
;;; For more information on EusLisp and its application to the robotics,
;;; please refer to the following papers.
;;;
;;; Toshihiro Matsui
;;; Multithread object-oriented language euslisp for parallel and
;;;  asynchronous programming in robotics
;;; Workshop on Concurrent Object-based Systems,
;;;  IEEE 6th Symposium on Parallel and Distributed Processing, 1994
;;;
;;; Permission to use this software for educational, research
;;; and non-profit purposes, without fee, and without a written
;;; agreement is hereby granted to all researchers working on
;;; the IRT project at the University of Tokyo, provided that the
;;; above copyright notice remains intact.  
;;;

(in-package "USER")

(require :irtrobot)

;;
;; bvh joint and link
;;

(defclass bvh-link
  :super bodyset-link
  :slots (type offset channels neutral))

(defmethod bvh-link
  (:init (name typ coords offst chs parent children rot)
         (let ((s 30) bs)
           (setq type typ offset offst channels chs)

           (setq bs (list (make-cube s s s)
			  (make-cube (* 0.1 s) (* 0.5 s) (* 0.5 s)  :pos (float-vector (* 0.60 s) 0 0))
			  (make-cylinder (* 0.5 s) (* 0.60 s))))
	   (dolist (b (cdr bs)) (send (car bs) :assoc b))
           (dolist (child children)
             (setq child (send coords :rotate-vector child))
             (let* ((v (v- (normalize-vector child)))
                    (c (make-cylinder (/ s 3.0) (norm child)))
                    (a (normalize-vector (v* v #f(0 0 1)))))
               (if (eps= (norm a) 0.0) (setq a #f(1 0 0)))
               (send c :rotate (acos (v. v #f(0 0 -1))) a)
               (send (car bs) :assoc c)
               (setq bs (nconc bs (list c)))))
           (send-super :init (make-cascoords :rot rot)
                       :bodies bs :name name)
           (case type
             ('end  (send self :bodies :set-color :red))
             ('root (send self :bodies :set-color :darkgreen))
             (t     (send self :bodies :set-color :green)))

           (setq offset (send coords :rotate-vector offset))
           (send self :locate
                 (if parent (v+ (send parent :worldpos) offset) offset) :world)
           (if parent (send parent :assoc self))
           (send self :worldcoords)
           self))
  (:type () type)
  (:offset () offset)
  (:channels () channels)
  )

(defclass bvh-sphere-joint
  :super sphere-joint
  :slots (axis-order bvh-default-rotation))
(defmethod bvh-sphere-joint
  (:init (&rest args &key (order (list :z :x :y)) ((:bvh-default-rotation bvh-rotation) (unit-matrix 3)) ((:bvh-offset-rotation bvh-offset) (unit-matrix 3)) &allow-other-keys)
         (setq axis-order order)
         (setq bvh-default-rotation (m* (transpose bvh-offset) bvh-rotation))
         (send-super* :init args))
  (:joint-angle-bvh
   (&optional v)
   (let (ja m)
     (when v
       (setq ja (map float-vector #'deg2rad v))
       (setq m (rotation-matrix (elt ja 2) (elt axis-order 2)))
       (rotate-matrix m (elt ja 1) (elt axis-order 1) t m)
       (rotate-matrix m (elt ja 0) (elt axis-order 0) t m)
       (send self :joint-angle (map float-vector #'rad2deg (transform bvh-default-rotation (matrix-log m))))
       )
     (map cons #'rad2deg (matrix-to-euler-angle (matrix-exponent (transform (transpose bvh-default-rotation) (matrix-log (send child-link :rot)))) axis-order))))
  (:axis-order () axis-order)
  )

(defclass bvh-6dof-joint
  :super 6dof-joint
  :slots (scale axis-order bvh-default-rotation))
(defmethod bvh-6dof-joint
  (:init (&rest args &key ((:scale scl)) (order (list :x :y :z :z :x :y)) ((:bvh-default-rotation bvh-rotation) (unit-matrix)) ((:bvh-offset-rotation bvh-offset) (unit-matrix 3)) &allow-other-keys)
         (setq scale (if scl scl 1.0)
               axis-order order
	       bvh-default-rotation (m* (transpose bvh-offset) bvh-rotation))
         (send-super* :init args))
  (:joint-angle-bvh
   (&optional v)
   (let (m r p)
     (when v
       (setq r (map float-vector #'deg2rad (subseq v 3 6))
             p (scale scale (subseq v 0 3)))
       (setq m (rotation-matrix (elt r 2) (elt axis-order 5)))
       (rotate-matrix m (elt r 1) (elt axis-order 4) t m)
       (rotate-matrix m (elt r 0) (elt axis-order 3) t m)
       (send self :joint-angle
             (concatenate float-vector
			  (transform bvh-default-rotation p)
			  (map cons #'rad2deg (transform bvh-default-rotation (matrix-log m))))))
     (concatenate cons
		  (transform (transpose bvh-default-rotation) (scale 0.001 (send child-link :pos)))
		  (map cons #'rad2deg (matrix-to-euler-angle (matrix-exponent (transform (transpose bvh-default-rotation) (matrix-log (send child-link :rot)))) (subseq axis-order 3 6))))))
  (:axis-order () axis-order))

(defclass bvh-robot-model
  :super robot-model
  :slots ())

(defmethod bvh-robot-model
  (:init
   (&rest args &key tree (coords (make-coords)) ((:scale scl)))
   (send-super* :init :coords (make-cascoords) args) ;; to avoid pass :coords keyword to upper-class
   (send self :make-bvh-link tree :coords coords :scale scl)
   (setq links (reverse links)
         joint-list (reverse joint-list))
   (send self :init-ending)
   self)
  (:make-bvh-link
   (tree &key parent (coords) ((:scale scl)))
   (let (joint-type joint-name offset channels alink ajoint)
     (setq joint-type (caar tree)
           joint-name (cadr (pop tree))
           offset (cadr (pop tree))
           channels (cdr (pop tree)))
     (if (null scl) (setq scl 1.0))
     (setq alink (instance bvh-link :init joint-name joint-type
                           coords
                           offset
			   (car channels)
                           parent
                           (mapcar #'(lambda (tr) (cadr (assoc 'offset (cdr tr)))) tree)
			   (send self :bvh-offset-rotate joint-name)
                           ))
     (push alink links)
     (unless (eql joint-type 'end)
       (let (joint-cls)
         (when (eql joint-type 'root)
             (setq parent (instance bodyset-link :init (make-cascoords) :name 'root-parent :bodies (list (make-cube 10 10 10))))
	     (send parent :assoc alink)
	     (send self :assoc parent))
         (case (car channels)
           (3 (setq joint-cls bvh-sphere-joint))
           (6 (setq joint-cls bvh-6dof-joint))
           (t (warning-message 1 "unknown joint type ~A~%" channels)))
         (setq ajoint (instance joint-cls :init :name joint-name
                                :child-link alink :parent-link parent
                                :bvh-default-rotation (send coords :worldrot)
                                :bvh-offset-rotation  (send self :bvh-offset-rotate joint-name)
                                :order (reduce #'(lambda (x y) (substitute (car y) (cdr y) x)) (list (cdr channels) (cons :x 'xrotation) (cons :y 'yrotation) (cons :z 'zrotation)))
                                :scale scl))
         (push ajoint joint-list)))
     (dolist (tr tree)
       (send self :make-bvh-link tr :parent alink :coords coords :scale scl))
     parent))
  (:bvh-offset-rotate (name) (unit-matrix 3))
  (:angle-vector
   (&optional vec
              (angle-vector (instantiate float-vector (calc-target-joint-dimension joint-list))))
   (let ((i 0) j)
     (dolist (j joint-list)
       (if vec
           (case (send j :joint-dof)
             (1 (send j :joint-angle (elt vec i)))
             (3 (let ((v (subseq vec i (+ i (send j :joint-dof)))))
		  (send j :joint-angle-bvh v)))
             (t (send j :joint-angle-bvh (subseq vec i (+ i (send j :joint-dof)))))
             ))
       (dotimes (k (send j :joint-dof))
         (setf (elt angle-vector i) (elt (send j :joint-angle-bvh) k))
         (incf i)))
     angle-vector))
  ;;
  (:dump-joints
   (links &key (depth 0) (strm *standard-output*))
   (let ((tabspace (fill (make-string (* depth 2)) #\space))
	 offset channels axis-order)
     (dolist (l links)
       (setq offset (send l :offset)
	     channels (send l :channels)
	     axis-order (send l :joint :axis-order))
       (format strm "~A~A ~A~%" tabspace (string-upcase (send l :type)) (send l :joint :name))
       (format strm "~A{~%" tabspace)
       (format strm "  ~AOFFSET ~0,6f ~0,6f ~0,6f~%" tabspace (elt offset 0) (elt offset 1) (elt offset 2))
       (format strm "  ~ACHANNELS ~A" tabspace channels)
       (dolist (axis axis-order)
	 (case axis
	   (:x (format strm " Xrotation"))
	   (:y (format strm " Yrotation"))
	   (:z (format strm " Zrotation"))
	   (t  (format strm " ~A" axis))))
       (format strm "~%")
       (if (send l :child-links)
	   (send self :dump-joints (reverse (send l :child-links))
		      :depth (1+ depth) :strm strm)
	 (let* ((end (find-if #'(lambda (x) (derivedp x bvh-link)) (send l :descendants)))
		(offset (send end :offset)))
	   (format strm "  ~AEnd Site~%" tabspace)
	   (format strm "  ~A{~%" tabspace)
	   (format strm "    ~A OFFSET ~0,6f ~0,6f ~0,6f~%" tabspace (elt offset 0) (elt offset 1) (elt offset 2))
	   (format strm "  ~A}~%" tabspace)
	   ))
       (format strm "~A}~%" tabspace)
     )))
  (:dump-hierarchy
   (&optional (strm *standard-output*))
   (format strm "HIERARCHY~%")
   (send self :dump-joints (list (car links)) :strm strm)
   (format strm "MOTION~%")
   (format strm "Frames: 100~%")
   (format strm "Frame Time: 0.033333~%")
   )
  (:dump-motion
   (&optional (strm *standard-output*))
   (let (a)
     (dolist (l links)
       (setq a (send l :joint :joint-angle-bvh))
       (dotimes (i (length a))
	 (format strm "~0,6f " (elt a i))))
     (format strm "~%")))
  (:copy-state-to
   (robot)
   (warning-message 1 "subclass's responsibility :copy-state-to~%")
   )
  ) ; bvh-robot-model

;;;
;;; bvh parser
;;;
;;; https://groups.google.com/group/comp.lang.lisp/browse_thread/thread/e9f2dd4f0a17810e/0be7675a3295f4e6?hl=ky&

(defun parse-bvh-sexp (src &key ((:scale scl)))
  (if (null scl) (setq scl 1.0))
  (if (atom src)
      src
    (let (op result)
      (while (setq op (pop src))
        (case op
          ((root joint end)
           (push (cons (list op (pop src)) (parse-bvh-sexp (pop src) :scale scl)) result))
          (offset
           (push (list op (scale scl (float-vector (pop src) (pop src) (pop src)))) result))
          (channels
           (push (cons op (do* ((i (pop src)) (r (list i)))
                              ((< (decf i) 0) (reverse r))
                            (push (pop src) r))) result))
          (t
           (if (symbolp op)
               (push (cons op (parse-bvh-sexp (pop src) :scale scl)) result)
             (push op result)))))
      (reverse result))))

(defun read-bvh (fname &key scale)
  (let ((*readtable* (copy-readtable))
        (eof (gensym)) hierarchy motions frames frame-time)
    (set-syntax-from-char #\# #\;) ;; commnet
    (set-syntax-from-char #\: #\ ) ;; fake :
    (set-syntax-from-char #\} #\)) ;; delimiter

    (set-macro-character
     #\{
     #'(lambda (strm ch)
         (read-delimited-list #\} strm t)))

    (with-open-file
     (strm fname :direction :input)

     (read strm) ;; check if hierarchy
     (do* ((item nil (read strm nil eof)))
         ((or (eql item eof) (eql item 'motion))
          (setq hierarchy (cdr (nreverse hierarchy))))
       (push item hierarchy))
     (setq hierarchy (car (parse-bvh-sexp hierarchy :scale scale)))

     (read strm) ;; frames
     (setq frames (read strm))

     (read strm) (read strm);; frame time
     (setq frame-time (read strm))
     (do* ((line "" (read-line strm nil nil)))
         ((not line))
       (let ((v (eval (read-from-string (format nil "(float-vector ~A)" line)))))
         (if (> (length v) 0) (push v motions))))
     (setq motions (nreverse motions))

     (warning-message 2 ";; Reading motion capture data from \"~A\"~%" fname)
     (warning-message 2 ";;  ~A joints, ~A frames~%" (length (car motions)) (length motions))

     `((hierarchy ,hierarchy)
       (motions ((frames ,frames) (frame-time ,frame-time) ,motions)))
     ) ;; with-open-file
    )); read-bvh

(defun make-bvh-robot-model (bvh-data &rest args)
  (instance* bvh-robot-model :init :tree bvh-data args))

(defclass motion-capture-data
  :super propertied-object
  :slots (frame model animation))
(defmethod motion-capture-data
  (:init
   (fname &key ((:scale scl)))
   (let (bvh-data)
     (setq bvh-data (read-bvh fname :scale scl))
     (setq model (make-bvh-robot-model (cadr (assoc 'hierarchy bvh-data)) :scale scl))
     (setq animation (car (last (cadr (assoc 'motions bvh-data)))))
     (setq frame 0)
     self))
  (:model (&rest args) (forward-message-to model args))
  (:animation (&rest args) (forward-message-to animation args))
  (:frame (&optional f)
   (if f (setq frame f))
   (send model :angle-vector (elt animation frame))
   frame)
  (:frame-length () (length animation))
  (:animate
   (&rest args &key (start 0) (step 1) (end (send self :frame-length)) (interval 20)  &allow-other-keys)
   (let ()
     (send self :frame start)
     (catch :animate
       (while t
	 (send self :frame frame)
	 (send (get *viewer* :pickviewer) :look-all)
	 (incf frame step)
	 (if (>= frame (send self :frame-length)) (throw :animate nil))
	 (if (select-stream (list *standard-input*) 1.0e-8) (throw :animate nil))
	 (if interval (unix:usleep (* 1000 interval)))
	 (x::window-main-one))) ;; catch
       ))
  ;;
  ) ; motion-capture-data

(defun bvh2eus (fname &key (scale))
  (let (b)
    (setq b (instance motion-capture-data :init fname :scale scale))
    (objects (list (send b :model)))
    (send b :animate)
    b))

;; CMU motion capture database
;; https://sites.google.com/a/cgspeed.com/cgspeed/motion-capture/cmu-bvh-conversion
;;
;; The TUM Kitchen Data Set
;; http://ias.cs.tum.edu/download/kitchen-activity-data
;;
;; Other Sites
;; http://www.mocapdata.com/page.cgi?p=free_motions
;; http://www.motekentertainment.com/
;; http://www.mocapclub.com/Pages/Library.htm

;;(bvh2eus "Take 005.bvh" :scale 10.0)
;;(bvh2eus "A01.bvh" :scale 10.0)
;;(bvh2eus "01_01.bvh" :scale 100.0)
;;(bvh2eus "poses.bvh")

(defmethod bvh-robot-model
  (:init-end-coords ()
   (setq larm-end-coords
	 (find-if  #'(lambda (x) (and (eq (send x :name) 'site)
				      (eq (send x :parent) (car (last larm))))) links)
	 rarm-end-coords
	 (find-if  #'(lambda (x) (and (eq (send x :name) 'site)
				      (eq (send x :parent) (car (last rarm))))) links)
	 lleg-end-coords
	 (find-if  #'(lambda (x) (and (eq (send x :name) 'site)
				      (eq (send x :parent) (car (last lleg))))) links)
	 rleg-end-coords
	 (find-if  #'(lambda (x) (and (eq (send x :name) 'site)
				      (eq (send x :parent) (car (last rleg))))) links)
	 torso-end-coords
	 (find-if  #'(lambda (x) (and (eq (send x :name) 'site)
				      (eq (send x :parent) (car (last torso))))) links)
	 head-end-coords
	 (find-if  #'(lambda (x) (and (eq (send x :name) 'site)
				      (eq (send x :parent) (car (last head))))) links)))
  (:init-root-link ()
   (setq larm-root-link (car larm) rarm-root-link (car rarm)
	 lleg-root-link (car lleg) rleg-root-link (car rleg)
	 torso-root-link (car torso)
	 head-root-link (car head)))
  ) ; defmethod bvh-robot-model


(defclass rikiya-bvh-robot-model
  :super bvh-robot-model
  :slots ())
(defmethod rikiya-bvh-robot-model
  (:init (&rest args)
   (send-super* :init :coords (make-coords :rpy (float-vector pi/2 0 pi/2)) args)
   (setq larm (list
	       (find 'leftcollar    links :key #'(lambda (x) (send x :name)))
	       (find 'leftshoulder  links :key #'(lambda (x) (send x :name)))
	       (find 'leftelbow     links :key #'(lambda (x) (send x :name)))
	       (find 'leftwrist     links :key #'(lambda (x) (send x :name))))
	 rarm (list
	       (find 'rightcollar   links :key #'(lambda (x) (send x :name)))
	       (find 'rightshoulder links :key #'(lambda (x) (send x :name)))
	       (find 'rightelbow    links :key #'(lambda (x) (send x :name)))
	       (find 'rightwrist    links :key #'(lambda (x) (send x :name))))
	 lleg (list
	       (find 'lefthip       links :key #'(lambda (x) (send x :name)))
	       (find 'leftknee      links :key #'(lambda (x) (send x :name)))
	       (find 'leftankle     links :key #'(lambda (x) (send x :name))))
	 rleg (list
	       (find 'righthip      links :key #'(lambda (x) (send x :name)))
	       (find 'rightknee     links :key #'(lambda (x) (send x :name)))
	       (find 'rightankle    links :key #'(lambda (x) (send x :name))))
	 torso (list
		(find 'chest        links :key #'(lambda (x) (send x :name))))
	 head  (list
		(find 'neck        links :key #'(lambda (x) (send x :name)))
		(find 'head        links :key #'(lambda (x) (send x :name)))))
   ;;
   (send self :init-end-coords)
   (send self :init-root-link)
   ;;;
   self) ;; init
  ) ;defmethod rikiya-bvh-robot-model

(defclass tum-bvh-robot-model
  :super bvh-robot-model
  :slots ())
(defmethod tum-bvh-robot-model
  (:init (&rest args)
   (send-super* :init :coords (make-coords :rpy (float-vector pi/2 0 0)) args)
   (setq larm (list
	       (find 'sb.l   links :key #'(lambda (x) (send x :name)))
	       (find 'oa.l   links :key #'(lambda (x) (send x :name)))
	       (find 'ua.l   links :key #'(lambda (x) (send x :name)))
	       (find 'ha.l   links :key #'(lambda (x) (send x :name)))
	       (find 'fi.l   links :key #'(lambda (x) (send x :name))))
	 rarm (list
	       (find 'sb.r   links :key #'(lambda (x) (send x :name)))
	       (find 'oa.r   links :key #'(lambda (x) (send x :name)))
	       (find 'ua.r   links :key #'(lambda (x) (send x :name)))
	       (find 'ha.r   links :key #'(lambda (x) (send x :name)))
	       (find 'fi.r   links :key #'(lambda (x) (send x :name))))
	 lleg (list
	       (find 'os.l   links :key #'(lambda (x) (send x :name)))
	       (find 'us.l   links :key #'(lambda (x) (send x :name)))
	       (find 'fu.l   links :key #'(lambda (x) (send x :name)))
	       (find 'fb.l   links :key #'(lambda (x) (send x :name))))
	 rleg (list
	       (find 'os.r   links :key #'(lambda (x) (send x :name)))
	       (find 'us.r   links :key #'(lambda (x) (send x :name)))
	       (find 'fu.r   links :key #'(lambda (x) (send x :name)))
	       (find 'fb.r   links :key #'(lambda (x) (send x :name))))
	 torso (list
		(find 'ulw   links :key #'(lambda (x) (send x :name)))
		(find 'olw   links :key #'(lambda (x) (send x :name)))
		(find 'ubw   links :key #'(lambda (x) (send x :name)))
		(find 'obw   links :key #'(lambda (x) (send x :name)))
		(find 'uhw   links :key #'(lambda (x) (send x :name)))
		(find 'brk   links :key #'(lambda (x) (send x :name))))
	 head  (list
		(find 'ohw   links :key #'(lambda (x) (send x :name)))
		(find 'ko    links :key #'(lambda (x) (send x :name)))))

   ;;
   (send self :init-end-coords)
   (send self :init-root-link)
   ;;
   self) ;; init
  ) ;defmethod tum-bvh-robot-model

(defclass cmu-bvh-robot-model
  :super bvh-robot-model
  :slots ())
(defmethod cmu-bvh-robot-model
  (:init (&rest args)
   (send-super* :init :coords (make-coords :rpy (float-vector pi/2 0 pi/2)) args)
   (setq larm (list
	       (find 'leftshoulder  links :key #'(lambda (x) (send x :name)))
	       (find 'leftarm       links :key #'(lambda (x) (send x :name)))
	       (find 'leftforearm   links :key #'(lambda (x) (send x :name)))
	       (find 'lefthand      links :key #'(lambda (x) (send x :name)))
	       (find 'lthumb       links :key #'(lambda (x) (send x :name))))
	 rarm (list
	       (find 'rightshoulder links :key #'(lambda (x) (send x :name)))
	       (find 'rightarm      links :key #'(lambda (x) (send x :name)))
	       (find 'rightforearm  links :key #'(lambda (x) (send x :name)))
	       (find 'righthand     links :key #'(lambda (x) (send x :name)))
	       (find 'rthumb       links :key #'(lambda (x) (send x :name))))
	 lleg (list
	       (find 'lhipjoint     links :key #'(lambda (x) (send x :name)))
	       (find 'leftupleg     links :key #'(lambda (x) (send x :name)))
	       (find 'leftleg	    links :key #'(lambda (x) (send x :name)))
	       (find 'leftfoot      links :key #'(lambda (x) (send x :name)))
	       (find 'lefttoebase   links :key #'(lambda (x) (send x :name))))
	 rleg (list
	       (find 'rhipjoint     links :key #'(lambda (x) (send x :name)))
	       (find 'rightupleg    links :key #'(lambda (x) (send x :name)))
	       (find 'rightleg	    links :key #'(lambda (x) (send x :name)))
	       (find 'rightfoot     links :key #'(lambda (x) (send x :name)))
	       (find 'righttoebase  links :key #'(lambda (x) (send x :name))))
	 torso (list
		(find 'lowerback    links :key #'(lambda (x) (send x :name)))
		(find 'spine        links :key #'(lambda (x) (send x :name)))
		(find 'spine1      links :key #'(lambda (x) (send x :name))))
	 head  (list
		(find 'neck        links :key #'(lambda (x) (send x :name)))
		(find 'neck1       links :key #'(lambda (x) (send x :name)))
		(find 'head        links :key #'(lambda (x) (send x :name)))))
   ;;
   (send self :init-end-coords)
   (send self :init-root-link)
   ;;;
   self) ;; init
  ) ;defmethod cmu-bvh-robot-model

(defun load-mcd (fname &key (scale) (bvh-robot-model-class bvh-robot-model))
  (let ((bvh-robot-model bvh-robot-model-class))
    (instance motion-capture-data :init fname :scale scale)
    ))

(in-package "GEOMETRY")

(provide :irtbvh "$Id: ")