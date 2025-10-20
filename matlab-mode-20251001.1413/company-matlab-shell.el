;;; company-matlab-shell.el --- a matlab-shell-mode completion back-end for MATLAB -*- lexical-binding: t -*-

;; Author: Eric Ludlam <zappo@gnu.org>, David Engster  <dengste@eml.cc>

;; Copyright (C) 2009-2024 Free Software Foundation, Inc.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License
;; as published by the Free Software Foundation; either version 3
;; of the License, or (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses>.

;;; Commentary:
;;

;;; Code:

(condition-case nil
    (require 'company)
  (error nil))

(require 'cl-macs)

(require 'matlab)
(require 'matlab-shell)

(defvar company-matlab-shell--ci (make-hash-table :test 'equal)
  "Private variable for `company-matlab-shell' completion info.")

(defun company-matlab-shell-grab-completion-substr ()
  "Return the completion substring of the command.
The completion substring is to be completed in `matlab-shell', or
\\='stop if completions can't be performed at the current point."
  (when (eq major-mode 'matlab-shell-mode)
    (if (not (matlab-on-prompt-p))
        'stop  ;; tell company can't complete when point is not in the prompt
      (let ((lastcmd (buffer-substring (point) (line-end-position))))
        ;; Kill the rest of the line since completion only works at the end of the line and
        ;; we'd like it to complete within a line. For example,
        ;;   h=figure;
        ;;   h.set('Vis','on')
        ;;             ^
        ;;             TAB here results in:
        ;;   h.set('Visible','on')
        (delete-region (point) (line-end-position))
        (let* ((buf-name (buffer-name (current-buffer)))
               (ci (matlab-shell-get-completion-info))
               (common-substr (cdr (assoc 'common-substr ci)))
               (did-completion (cdr (assoc 'did-completion ci))))
          ;; restore the killed part of the line
          (let ((orig-pt (point)))
            (insert lastcmd)
            (goto-char orig-pt))

          ;; If did-completion, then matlab-shell-get-completion-info updated the
          ;; *MATLAB* buffer by deleting text and calling (insert replacement-text), and
          ;; we have no more completion info.
          (if did-completion
              ;; Tell company to abort completion. This causes "Cannot complete at point" and
              ;; there doesn't seem to be a way to protect against this message.
              nil
            (puthash buf-name ci company-matlab-shell--ci)
            ;; command to be completed
            common-substr
            ))))))

(defun company-matlab-shell-get-completions ()
  "Get matlab-shell completions."
  (let* ((ci (if (eq major-mode 'matlab-shell-mode)
                 (gethash (buffer-name (current-buffer)) company-matlab-shell--ci)))
         (completions (if ci (cdr (assoc 'completions ci)))))
    (if ci (remhash (buffer-name (current-buffer)) company-matlab-shell--ci))
    (mapcar 'car completions)))

;;;###autoload
(defun company-matlab-shell (command &optional arg &rest ignored)
  "A `company-mode' completion backend for `matlab-shell'.
COMMAND is the item to complete.
ARG and IGNORED are ignored."
  (interactive (list 'interactive))
  (ignore arg ignored)
  (cl-case command
    ( interactive (if (fboundp 'company-begin-backend) ;; quiet warning when no company
                      (company-begin-backend 'company-matlab-shell)
                    (error "Unable to provide completions - company-begin-backend is missing")))
    ( prefix      (company-matlab-shell-grab-completion-substr))
    ( candidates  (company-matlab-shell-get-completions))
    ( sorted      t)))

(provide 'company-matlab-shell)
;;; company-matlab-shell.el ends here

;; LocalWords:  Ludlam Engster ci defun substr lastcmd eol buf cdr puthash gethash remhash mapcar
;; LocalWords:  fboundp zappo dengste
