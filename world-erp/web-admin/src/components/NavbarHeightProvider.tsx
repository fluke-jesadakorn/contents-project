'use client';

import { useEffect } from 'react';

const NAVBAR_SELECTOR = 'header[role="banner"]';
const ANCHOR_SELECTOR = '.org-anchor';
const ROOT_STYLE_PROP = '--navbar-h';
const ANCHOR_STYLE_PROP = '--anchor-h';

const FALLBACK_NAVBAR = '56px';

function setVar(root: HTMLElement, name: string, value: string): void {
  root.style.setProperty(name, value);
}

export const NavbarHeightProvider: React.FC = () => {
  useEffect(() => {
    const root = document.documentElement;
    if (!root) return;

    const navbarObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const h = entry.contentRect.height;
        if (h > 0) setVar(root, ROOT_STYLE_PROP, `${Math.round(h)}px`);
      }
    });

    const anchorObserver = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const h = entry.contentRect.height;
        if (h > 0) setVar(root, ANCHOR_STYLE_PROP, `${Math.round(h)}px`);
      }
    });

    const navbar = document.querySelector<HTMLElement>(NAVBAR_SELECTOR);
    if (navbar) {
      navbarObserver.observe(navbar);
    } else {
      setVar(root, ROOT_STYLE_PROP, FALLBACK_NAVBAR);
    }

    const connectAnchor = () => {
      const anchor = document.querySelector<HTMLElement>(ANCHOR_SELECTOR);
      if (anchor) {
        anchorObserver.observe(anchor);
      } else {
        setTimeout(connectAnchor, 250);
      }
    };
    connectAnchor();

    const onResize = () => {
      const n = document.querySelector<HTMLElement>(NAVBAR_SELECTOR);
      const a = document.querySelector<HTMLElement>(ANCHOR_SELECTOR);
      if (n) setVar(root, ROOT_STYLE_PROP, `${Math.round(n.getBoundingClientRect().height)}px`);
      if (a) setVar(root, ANCHOR_STYLE_PROP, `${Math.round(a.getBoundingClientRect().height)}px`);
    };
    window.addEventListener('resize', onResize);

    return () => {
      navbarObserver.disconnect();
      anchorObserver.disconnect();
      window.removeEventListener('resize', onResize);
    };
  }, []);

  return null;
};

export default NavbarHeightProvider;
