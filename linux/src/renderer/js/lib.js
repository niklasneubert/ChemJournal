// Gemeinsame Bausteine: Preact + htm (ohne Build-Schritt), Zugriff auf die gemeinsamen Module (window.CJ).
import { h, render, Fragment } from '../vendor/preact.module.js';
import { useState, useEffect, useRef, useMemo, useCallback, useLayoutEffect } from '../vendor/hooks.module.js';
import htm from '../vendor/htm.module.js';

export const html = htm.bind(h);
export { h, render, Fragment, useState, useEffect, useRef, useMemo, useCallback, useLayoutEffect };
export const CJ = window.CJ;
export const api = window.chemjournal;

/** Swift-Datum (Sekunden seit 1.1.2001) ↔ JavaScript */
const REF = Date.UTC(2001, 0, 1);
export const nowRef = () => (Date.now() - REF) / 1000;
export const refToDate = s => new Date(REF + s * 1000);
export const uuid = () => crypto.randomUUID().toUpperCase();

const dateLong = new Intl.DateTimeFormat('de-DE', { dateStyle: 'long' });
const dateShort = new Intl.DateTimeFormat('de-DE', { day: 'numeric', month: 'short', year: 'numeric' });
const timeShort = new Intl.DateTimeFormat('de-DE', { hour: '2-digit', minute: '2-digit' });
const dateNumeric = new Intl.DateTimeFormat('de-DE', { day: '2-digit', month: '2-digit', year: 'numeric' });
export const formatLong = d => dateLong.format(d);
/** wie Swift .formatted(date: .abbreviated, time: .shortened) */
export const formatAbbrevTime = d => `${dateShort.format(d)}, ${timeShort.format(d)}`;
export const formatAbbrev = d => dateShort.format(d);
export const formatNumeric = d => dateNumeric.format(d);
export const formatTime = d => timeShort.format(d);

export function formatBytes(n) {
  if (n < 1000) return `${n} Byte`;
  if (n < 1e6) return `${Math.round(n / 1000)} KB`;
  return `${(n / 1e6).toFixed(1).replace('.', ',')} MB`;
}

// Neue Objekte im Format der Mac-App
export const newChemical = () => ({ id: uuid(), name: '', equivalents: '', cas: '', molarMass: '', density: '', amount: '', volume: '', mass: '' });
export const newYield = () => ({ id: uuid(), name: '', cas: '', molarMass: '', density: '', amount: '', volume: '', mass: '' });
export const newStage = title => ({ id: uuid(), title, sourceURL: '', summary: '', procedure: '', observation: '', chemicals: [], yieldProducts: [], analysisFiles: [], isExpanded: true, createdAt: nowRef() });
export const newExperiment = (title = 'Neuer Ansatz') => ({ id: uuid(), title, summary: '', stages: [], createdAt: nowRef(), updatedAt: nowRef() });
export const newProject = (title = 'Neues Projekt') => ({ id: uuid(), title, isExpanded: true, experiments: [] });
