;;; linemark.el --- Manage groups of lines with marks. -*- lexical-binding: t -*-

;; Author: Eric M. Ludlam <eludlam@mathworks.com>
;; Maintainer: Eric M. Ludlam <eludlam@mathworks.com>
;; Created: Dec 1999
;; Keywords: lisp

;; Copyright (C) 2013-2025 Free Software Foundation, Inc.
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3, or (at your option)
;; any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs; see the file COPYING.  If not, write to the
;; Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor,
;; Boston, MA 02110-1301, USA.
;;
;;; Commentary:
;;
;; This is a library of routines which help Lisp programmers manage
;; groups of marked lines.  Common uses for marked lines are debugger
;; breakpoints and watchpoints, or temporary line highlighting.  It
;; could also be used to select elements from a list.
;;
;; The reason this tool is useful is because cross-emacs overlay
;; management can be a pain, and overlays are certainly needed for use
;; with font-lock.

(eval-and-compile
  (require 'matlab-compat))

(require 'eieio)

;;; Code:

(defgroup linemark nil
  "Line marking/highlighting."
  :group 'tools
  )

(eval-and-compile
  ;; These faces need to exist to show up as valid default
  ;; entries in the classes defined below.

  (defface linemark-stop-face '((((class color) (background light))
                                 (:background "#ff8888"))
                                (((class color) (background dark))
                                 (:background "red3")))
    "*Face used to indicate a STOP type line."
    :group 'linemark)

  (defface linemark-caution-face '((((class color) (background light))
                                    (:background "yellow"))
                                   (((class color) (background dark))
                                    (:background "yellow4")))
    "*Face used to indicate a CAUTION type line."
    :group 'linemark)

  (defface linemark-go-face '((((class color) (background light))
                               (:background "#88ff88"))
                              (((class color) (background dark))
                               (:background "green4")))
    "*Face used to indicate a GO, or OK type line."
    :group 'linemark)

  (defface linemark-funny-face '((((class color) (background light))
                                  (:background "cyan"))
                                 (((class color) (background dark))
                                  (:background "blue3")))
    "*Face used for elements with no particular criticality."
    :group 'linemark)

  )

(defclass linemark-entry ()
  ((filename :initarg :filename
             :type string
             :documentation "File name for this mark.")
   (line     :initarg :line
             :type number
             :documentation "Line number where the mark is.")
   (face     :initarg :face
             :initform 'linemark-caution-face
             :documentation "The face to use for display.")
   (parent   :documentation "The parent `linemark-group' containing this."
             :type linemark-group)
   (overlay  :documentation "Overlay created to show this mark."
             :type (or overlay null)
             :initform nil
             :protection protected))
  "Track a file/line associations with overlays used for display.")

(defclass linemark-group ()
  ((marks :initarg :marks
          :type list
          :initform nil
          :documentation "List of `linemark-entries'.")
   (face :initarg :face
         :initform 'linemark-funny-face
         :documentation "Default face used to create new `linemark-entries'.")
   (active :initarg :active
           :type boolean
           :initform t
           :documentation "Track if these marks are active or not."))
  "Track a common group of `linemark-entries'.")

;;; Functions
;;
(defvar linemark-groups nil
  "List of groups we need to track.")

(defun linemark-create-group (name &optional defaultface)
  "*Obsolete*.
Create a group object for tracking linemark entries.
Do not permit multiple groups with the same NAME.
Optional argument DEFAULTFACE is the :face slot for the object."
  (linemark-new-group 'linemark-group name :face defaultface)
  )

(defun linemark-new-group (class name &rest args)
  "Create a new linemark group based on the linemark CLASS.
Give this group NAME.  ARGS are slot/value pairs for
the new instantiation."
  (let ((newgroup nil)
        (foundgroup nil)
        (lmg linemark-groups))
    ;; Find an old group.
    (while (and (not foundgroup) lmg)
      (if (string= name (eieio-object-name-string (car lmg)))
          (setq foundgroup (car lmg)))
      (setq lmg (cdr lmg)))
    ;; Which group to use.
    (if foundgroup
        ;; Recycle the old group
        (setq newgroup foundgroup)
      ;; Create a new group
      (setq newgroup (apply 'make-instance class name args))
      (setq linemark-groups (cons newgroup linemark-groups)))
    ;; Return the group
    newgroup))

(defun linemark-at-point (&optional pos group)
  "Return the current variable `linemark-entry' at point.
Optional POS is the position to check which defaults to point.
If GROUP, then make sure it also belongs to GROUP."
  (if (not pos) (setq pos (point)))
  (let ((o (overlays-at pos))
        (found nil))
    (while (and o (not found))
      (let ((og (overlay-get (car o) 'obj)))
        (if (and og (linemark-entry--eieio-childp og))
            (progn
              (setq found og)
              (if group
                  (if (not (eq group (oref found parent)))
                      (setq found nil)))))
        (setq o (cdr o))))
    found))

(defun linemark-next-in-buffer (group &optional arg wrap)
  "Return the next mark in this buffer belonging to GROUP.
If ARG, then find that many marks forward or backward.
Optional WRAP argument indicates that we should wrap around the end of
the buffer."
  (if (not arg) (setq arg 1)) ;; default is one forward
  (let* ((entry (linemark-at-point (point) group))
         (nc (if entry
                 (if (< 0 arg) (linemark-end entry)
                   (linemark-begin entry))
               (point)))
         (dir (if (< 0 arg) 1 -1))
         (ofun (if (> 0 arg)
                   'previous-overlay-change
                 'next-overlay-change))
         (bounds (if (< 0 arg) (point-min) (point-max)))
         )
    (setq entry nil)
    (catch 'moose
      (save-excursion
        (while (and (not entry) (/= arg 0))
          (setq nc (funcall ofun nc))
          (setq entry (linemark-at-point nc group))
          (if (not entry)
              (if (or (= nc (point-min)) (= nc (point-max)))
                  (if (not wrap)
                      (throw 'moose t)
                    (setq wrap nil ;; only wrap once
                          nc bounds))))
          ;; Ok, now decrement arg, and keep going.
          (if entry
              (setq arg (- arg dir)
                    nc (linemark-end entry))))))
    entry))

;;; Methods that make things go
;;
(cl-defmethod linemark-add-entry ((g linemark-group) &rest args)
  "Add a `linemark-entry' to G.
It will be at location specified by :filename and :line, and :face
which are property list entries in ARGS.
Call the new entries activate method."
  (let ((file (plist-get args :filename))
        (line (plist-get args :line))
        (face (plist-get args :face)))
    (if (not file)
        (progn
          (setq file (buffer-file-name))
          (if file
              (setq file (expand-file-name file))
            (setq file (buffer-name)))))
    (when (not line)
      (setq line (count-lines (point-min) (point)))
      (if (bolp) (setq line (1+ line))))
    (setq args (plist-put args :filename file))
    (setq args (plist-put args :line line))
    (let ((new-entry (apply 'linemark-new-entry g args)))
      (oset new-entry parent g)
      (oset new-entry face (or face (oref g face)))
      (oset g marks (cons new-entry (oref g marks)))
      (if (oref g active)
          (condition-case nil
              ;; Somewhere in the eieio framework this can throw 'end of buffer' error
              ;; after the display function exits.  Not sure where that is, but this
              ;; condition-case can capture it and allow things to keep going.
              (linemark-display new-entry t)
            (error nil)))
      new-entry)
    ))

(cl-defmethod linemark-new-entry ((g linemark-group) &rest args)
  "Create a new entry for G using init ARGS."
  (ignore g)
  (let ((f (plist-get args :filename))
        (l (plist-get args :line)))
    (apply 'linemark-entry (format "%s %d" f l)
           args)))

(cl-defmethod linemark-display ((g linemark-group) active-p)
  "Set object G to be active or inactive based on ACTIVE-P."
  (mapc (lambda (g) (linemark-display g active-p)) (oref g marks))
  (oset g active active-p))

(cl-defmethod linemark-display ((e linemark-entry) active-p)
  "Set object E to be active or inactive based on ACTIVE-P."
  (if active-p
      (with-slots ((file filename)) e
        (if (oref e overlay)
            ;; Already active
            nil
          (let ((buffer))
            (if (get-file-buffer file)
                (setq buffer (get-file-buffer file))
              (setq buffer (get-buffer file)))
            (if buffer
                (with-current-buffer buffer
                  (save-excursion
                    (goto-char (point-min))
                    (forward-line (1- (oref e line)))
                    (oset e overlay
                          (make-overlay (point)
                                        (save-excursion
                                          (end-of-line) (point))
                                        (current-buffer)))
                    (with-slots (overlay) e
                      (overlay-put overlay 'face (oref e face))
                      (overlay-put overlay 'obj e)
                      (overlay-put overlay 'tag 'linemark))))))))
    ;; Not active
    (with-slots (overlay) e
      (if overlay
          (progn
            (condition-case nil
                ;; During development of linemark programs, this is helpful
                (delete-overlay overlay)
              (error nil))
            (oset e overlay nil))))))

(cl-defmethod linemark-delete ((g linemark-group))
  "Remove group G from linemark tracking."
  (mapc 'linemark-delete (oref g marks))
  (setq linemark-groups (delete g linemark-groups)))

(cl-defmethod linemark-delete ((e linemark-entry))
  "Remove entry E from it's parent group."
  (with-slots (parent) e
    (oset parent marks (delq e (oref parent marks)))
    (linemark-display e nil)))

(cl-defmethod linemark-begin ((e linemark-entry))
  "Position at the start of the entry E."
  (with-slots (overlay) e
    (overlay-start overlay)))

(cl-defmethod linemark-end ((e linemark-entry))
  "Position at the end of the entry E."
  (with-slots (overlay) e
    (overlay-end overlay)))

;;; Trans buffer tracking
;;
;; This section sets up a find-file-hook and a kill-buffer-hook
;; so that marks that aren't displayed (because the buffer doesn't
;; exist) are displayed when said buffer appears, and that overlays
;; are removed when the buffer goes away.

(defun linemark-find-file-hook ()
  "Activate all linemarks which can benefit from this new buffer."
  (mapcar (lambda (g) (condition-case nil
                          ;; See comment in linemark-add-entry for
                          ;; reasoning on this condition-case.
                          (linemark-display g t)
                        (error nil)))
          linemark-groups))

(defun linemark-kill-buffer-hook ()
  "Deactivate all entries in the current buffer."
  (let ((o (overlays-in (point-min) (point-max)))
        (to nil))
    (while o
      (setq to (overlay-get (car o) 'obj))
      (if (and to (linemark-entry--eieio-childp to))
          (linemark-display to nil))
      (setq o (cdr o)))))

(add-hook 'find-file-hook 'linemark-find-file-hook)
(add-hook 'kill-buffer-hook 'linemark-kill-buffer-hook)

;;; Demo mark tool: Emulate MS Visual Studio bookmarks
;;
(defvar viss-bookmark-group (linemark-new-group 'linemark-group "viss")
  "The VISS bookmark group object.")

(defun viss-bookmark-toggle ()
  "Toggle a bookmark on the current line."
  (interactive)
  (let ((ce (linemark-at-point (point) viss-bookmark-group)))
    (if ce
        (linemark-delete ce)
      (linemark-add-entry viss-bookmark-group))))

(defun viss-bookmark-next-buffer ()
  "Move to the next bookmark in this buffer."
  (interactive)
  (let ((n (linemark-next-in-buffer viss-bookmark-group 1 t)))
    (if n
        (progn
          (goto-char (point-min))
          (forward-line (1- (oref n line))))
      (ding))))

(defun viss-bookmark-prev-buffer ()
  "Move to the next bookmark in this buffer."
  (interactive)
  (let ((n (linemark-next-in-buffer viss-bookmark-group -1 t)))
    (if n
        (progn
          (goto-char (point-min))
          (forward-line (1- (oref n line))))
      (ding))))

(defun viss-bookmark-clear-all-buffer ()
  "Clear all bookmarks in this buffer."
  (interactive)
  (mapcar (lambda (e)
            (if (or (string= (oref e filename) (buffer-file-name))
                    (string= (oref e filename) (buffer-name)))
                (linemark-delete e)))
          (oref viss-bookmark-group marks)))

;; These functions only sort of worked and were not really useful to me.
;;
;;(defun viss-bookmark-next ()
;;  "Move to the next bookmark."
;;  (interactive)
;;  (let ((c (linemark-at-point (point) viss-bookmark-group))
;;        (n nil))
;;    (if c
;;        (let ((n (member c (oref viss-bookmark-group marks))))
;;          (if n (setq n (car (cdr n)))
;;            (setq n (car (oref viss-bookmark-group marks))))
;;          (if n (goto-line (oref n line)) (ding)))
;;      ;; if no current mark, then just find a local one.
;;      (viss-bookmark-next-buffer))))
;;
;;(defun viss-bookmark-prev ()
;;  "Move to the next bookmark."
;;  (interactive)
;;  (let ((c (linemark-at-point (point) viss-bookmark-group))
;;        (n nil))
;;    (if c
;;        (let* ((marks (oref viss-bookmark-group marks))
;;               (n (member c marks)))
;;          (if n
;;              (setq n (- (- (length marks) (length n)) 1))
;;            (setq n (car marks)))
;;          (if n (goto-line (oref n line)) (ding)))
;;      ;; if no current mark, then just find a local one.
;;      (viss-bookmark-prev-buffer))))
;;
;;(defun viss-bookmark-clear-all ()
;;  "Clear all viss bookmarks."
;;  (interactive)
;;  (mapcar (lambda (e) (linemark-delete e))
;;          (oref viss-bookmark-group marks)))
;;

;;;###autoload
(defun enable-visual-studio-bookmarks ()
  "Bind the viss bookmark functions to F2 related keys.
\\<global-map>
\\[viss-bookmark-toggle]     - Toggle a bookmark on this line.
\\[viss-bookmark-next-buffer]   - Move to the next bookmark.
\\[viss-bookmark-prev-buffer]   - Move to the previous bookmark.
\\[viss-bookmark-clear-all-buffer] - Clear all bookmarks."
  (interactive)
  (define-key global-map [(f2)] 'viss-bookmark-toggle)
  (define-key global-map [(shift f2)] 'viss-bookmark-prev-buffer)
  (define-key global-map [(control f2)] 'viss-bookmark-next-buffer)
  (define-key global-map [(control shift f2)] 'viss-bookmark-clear-all-buffer)
  )

(provide 'linemark)

;;; linemark.el ends here

;; LocalWords:  Ludlam eludlam compat defface defclass initarg initform defun defaultface newgroup
;; LocalWords:  foundgroup lmg eieio setq cdr og childp progn oref nc ofun funcall defmethod plist
;; LocalWords:  bolp oset mapc delq linemarks mapcar viss ce prev
